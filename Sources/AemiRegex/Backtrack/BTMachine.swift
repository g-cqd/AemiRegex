/// Runs a ``BTProgram`` over a haystack with an explicit stack. One value serves one public call, so its budget is shared by every search
/// that call makes.
struct BTMachine {
    let program: BTProgram
    let budget: BacktrackingPattern.Budget
    var slots: [Int]
    var stack: [BTEntry] = []
    /// Stack indices of the atomic groups and look-arounds that are still open, innermost last.
    var marks: [Int] = []
    var steps = 0
    /// A match that is empty and sits here is refused, so the search goes on (PCRE2's `NOTEMPTY_ATSTART`).
    var forbiddenEmpty: Int?
    let lineTerminators: ScalarSet

    init(_ program: BTProgram, budget: BacktrackingPattern.Budget) {
        self.program = program
        self.budget = budget
        slots = [Int](repeating: -1, count: program.slotCount)
        lineTerminators = BTSets.lineTerminators(program.dialect)
    }

    /// The leftmost match that starts at or after `start`, trying each scalar boundary in turn.
    /// - Parameters:
    ///   - bytes: The text to search.
    ///   - start: Where the search begins.
    ///   - anchored: Whether the match must start exactly at `start`.
    ///   - nonEmptyAtStart: Whether an empty match at `start` is not a match (PCRE2's retry after an empty match).
    /// - Returns: The match, or `nil` when there is none.
    /// - Throws: ``BacktrackError`` when a budget runs out.
    mutating func firstMatch(
        in bytes: ByteBuffer, from start: Int, anchored: Bool = false, nonEmptyAtStart: Bool = false
    ) throws(BacktrackError) -> Match? {
        guard start >= 0, start <= bytes.count else { return nil }
        forbiddenEmpty = nonEmptyAtStart ? start : nil
        defer { forbiddenEmpty = nil }
        var begin = start
        while begin <= bytes.count {
            if try run(in: bytes, from: begin) { return match() }
            if anchored || begin == bytes.count { break }
            begin += ScalarReader.step(in: bytes, at: begin)
        }
        return nil
    }

    private func match() -> Match {
        var captures: [Range<Int>?] = []
        captures.reserveCapacity(program.captureCount)
        for group in 1 ..< program.captureCount + 1 {
            let (open, close) = (slots[2 * group], slots[2 * group + 1])
            captures.append(open >= 0 && close >= open ? open ..< close : nil)
        }
        return Match(range: slots[0] ..< slots[1], captures: captures)
    }

    private mutating func run(in bytes: ByteBuffer, from start: Int) throws(BacktrackError) -> Bool {
        for index in slots.indices { slots[index] = -1 }
        stack.removeAll(keepingCapacity: true)
        marks.removeAll(keepingCapacity: true)
        slots[0] = start
        var pc = 0
        var pos = start
        while true {
            steps += 1
            if steps > budget.maxSteps { throw .budgetExceeded(.steps) }
            switch try execute(program.code[pc], in: bytes, pc: &pc, pos: &pos) {
                case .next: continue
                case .matched: return true
                case .failed: if !backtrack(&pc, &pos) { return false }
            }
        }
    }

    private enum Step {
        case next
        case failed
        case matched
    }

    /// Runs one instruction, moving `pc` and `pos` on.
    private mutating func execute(
        _ instruction: BTInstruction, in bytes: ByteBuffer, pc: inout Int, pos: inout Int
    ) throws(BacktrackError) -> Step {
        var ok = true
        switch instruction.op {
            case .char, .set:
                ok = consume(instruction, in: bytes, at: &pos)
                pc += 1
            case .split:
                try push(.choice, pc + Int(instruction.y), pos)
                pc += Int(instruction.x)
            case .jump:
                pc += Int(instruction.x)
            case .save, .setRegister:
                try write(slot: Int(instruction.x), pos)
                pc += 1
            case .assertion:
                ok = holds(BTAssertion(rawValue: instruction.x) ?? .beginText, in: bytes, at: pos)
                pc += 1
            case .backReference:
                ok = try reference(instruction, in: bytes, at: &pos)
                pc += 1
            case .lookStart:
                marks.append(stack.count)
                if instruction.x == 1 {
                    try push(.lookNegative, pc + Int(instruction.y), pos)
                } else {
                    try push(.lookPositive, 0, pos)
                }
                pc += 1
            case .lookEnd:
                guard let mark = marks.popLast() else { return .failed }
                if instruction.x == 1 {
                    undo(to: mark)
                    ok = false
                } else {
                    pos = stack[mark].b
                    close(mark)
                    pc += 1
                }
            case .atomicStart:
                marks.append(stack.count)
                try push(.atomicOpen, 0, pos)
                pc += 1
            case .atomicEnd:
                guard let mark = marks.popLast() else { return .failed }
                close(mark)
                pc += 1
            case .emptyCheck:
                if pos == slots[Int(instruction.x)] {
                    if instruction.y == 0 { ok = false } else { pc += Int(instruction.y) }
                } else {
                    pc += 1
                }
            case .resetCaptures:
                try reset(groups: Int(instruction.x) ..< Int(instruction.y))
                pc += 1
            case .stepBack:
                for _ in 0 ..< Int(instruction.x) {
                    guard let before = ScalarReader.scalar(in: bytes, before: pos) else {
                        ok = false
                        break
                    }
                    pos -= before.width
                }
                pc += 1
            case .endAt:
                ok = marks.last.map { stack[$0].b == pos } ?? false
                pc += 1
            case .keep:
                try write(slot: 0, pos)
                pc += 1
            case .fail:
                ok = false
            case .match:
                guard let forbidden = forbiddenEmpty, pos == forbidden, slots[0] == pos else {
                    slots[1] = pos
                    return .matched
                }
                ok = false
        }
        return ok ? .next : .failed
    }

    // MARK: Stack

    private mutating func push(_ tag: BTEntry.Tag, _ a: Int, _ b: Int) throws(BacktrackError) {
        guard stack.count < budget.maxStackEntries else { throw .budgetExceeded(.stack) }
        stack.append(BTEntry(tag: tag, a: a, b: b))
    }

    private mutating func write(slot: Int, _ value: Int) throws(BacktrackError) {
        try push(.restore, slot, slots[slot])
        slots[slot] = value
    }

    private mutating func reset(groups: Range<Int>) throws(BacktrackError) {
        for group in groups {
            for slot in [2 * group, 2 * group + 1] where slots[slot] >= 0 { try write(slot: slot, -1) }
        }
    }

    /// Resumes the most recent choice, undoing what was done since. Returns `false` when none is left.
    private mutating func backtrack(_ pc: inout Int, _ pos: inout Int) -> Bool {
        while let entry = stack.popLast() {
            switch entry.tag {
                case .choice:
                    pc = entry.a
                    pos = entry.b
                    return true
                case .restore: slots[entry.a] = entry.b
                case .atomicOpen, .lookPositive: _ = marks.popLast()
                case .lookNegative:
                    _ = marks.popLast()
                    pc = entry.a
                    pos = entry.b
                    return true
                case .inert: break
            }
        }
        return false
    }

    /// Ends an atomic group or a positive look-around: its choice points go, its undo records stay.
    private mutating func close(_ mark: Int) {
        var write = mark + 1
        for read in (mark + 1) ..< stack.count where stack[read].tag == .restore || stack[read].tag == .inert {
            stack[write] = stack[read]
            write += 1
        }
        stack.removeSubrange(write...)
        stack[mark].tag = .inert
    }

    /// Takes back everything done since `mark`, the mark included.
    private mutating func undo(to mark: Int) {
        while stack.count > mark {
            let entry = stack.removeLast()
            if entry.tag == .restore { slots[entry.a] = entry.b }
        }
    }

    // MARK: Consuming

    private func consume(_ instruction: BTInstruction, in bytes: ByteBuffer, at pos: inout Int) -> Bool {
        let found =
            instruction.backward ? ScalarReader.scalar(in: bytes, before: pos) : ScalarReader.scalar(in: bytes, at: pos)
        guard let (value, width) = found else { return false }
        if instruction.op == .char {
            guard value == UInt32(truncatingIfNeeded: instruction.x) else { return false }
        } else {
            guard program.sets[Int(instruction.x)].contains(value) else { return false }
        }
        pos += instruction.backward ? -width : width
        return true
    }
}
