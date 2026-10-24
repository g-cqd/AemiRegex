/// A Pike VM: simulates every thread of the pattern in lock step over the input, so the time is O(pattern × input) for every
/// pattern. The thread order is the priority order, which gives leftmost-first matches with captures.
struct PikeVM {
    private enum Entry {
        case explore(Int)
        case restore(slot: Int, value: Int)
    }

    private let program: Program
    private let slotCount: Int
    private var current: ThreadList
    private var next: ThreadList
    private var working: [Int]
    private var stack: [Entry] = []
    /// The capture slots of the last match found, or all -1.
    private(set) var best: [Int]

    init(_ program: Program) {
        self.program = program
        slotCount = program.slotCount
        let count = program.instructions.count
        current = ThreadList(instructionCount: count, slotCount: slotCount)
        next = ThreadList(instructionCount: count, slotCount: slotCount)
        working = [Int](repeating: -1, count: slotCount)
        best = working
    }

    /// Finds the leftmost-first match that starts at or after `start`. Assertions see the bytes before `start`.
    /// - Returns: `true` when a match was found; its slots are in ``best``.
    mutating func search(_ haystack: [UInt8], from start: Int) -> Bool {
        let length = haystack.count
        var found = false
        current.set.removeAll()
        next.set.removeAll()
        var position = start
        while true {
            if !found, Self.isBoundary(haystack, position) {
                for index in 0 ..< slotCount { working[index] = -1 }
                working[0] = position
                follow(0, at: position, haystack, intoNext: false)
            }
            if current.set.isEmpty {
                if found || position >= length { break }
                position += 1
                continue
            }
            next.set.removeAll()
            let byte = position < length ? Int(haystack[position]) : -1
            var index = 0
            while index < current.set.count {
                let pc = Int(current.set.dense[index])
                let instruction = program.instructions[pc]
                switch instruction.op {
                    case .match:
                        for slot in 0 ..< slotCount { best[slot] = current.slots[pc * slotCount + slot] }
                        best[1] = position
                        found = true
                        index = current.set.count
                    case .byteRange:
                        if byte >= Int(instruction.x), byte <= Int(instruction.y) {
                            advance(from: pc, to: position + 1, haystack)
                        }
                    case .byteSet:
                        if byte >= 0, program.sets[Int(instruction.x)].contains(UInt8(truncatingIfNeeded: byte)) {
                            advance(from: pc, to: position + 1, haystack)
                        }
                    case .split, .jump, .save, .assertion:
                        break
                }
                index += 1
            }
            swap(&current, &next)
            if position >= length { break }
            position += 1
        }
        return found
    }

    /// Moves the thread at `pc` past its byte instruction, into the next list.
    private mutating func advance(from pc: Int, to position: Int, _ haystack: [UInt8]) {
        for slot in 0 ..< slotCount { working[slot] = current.slots[pc * slotCount + slot] }
        follow(pc + 1, at: position, haystack, intoNext: true)
    }

    /// Adds the thread at `start` and every thread reachable from it without consuming input, in priority order.
    private mutating func follow(_ start: Int, at position: Int, _ haystack: [UInt8], intoNext: Bool) {
        stack.append(.explore(start))
        while let entry = stack.popLast() {
            switch entry {
                case .restore(let slot, let value):
                    working[slot] = value
                case .explore(let pc):
                    if intoNext ? next.set.contains(pc) : current.set.contains(pc) { continue }
                    if intoNext { next.set.insert(pc) } else { current.set.insert(pc) }
                    let instruction = program.instructions[pc]
                    switch instruction.op {
                        case .jump:
                            stack.append(.explore(pc + Int(instruction.x)))
                        case .split:
                            stack.append(.explore(pc + Int(instruction.y)))
                            stack.append(.explore(pc + Int(instruction.x)))
                        case .save:
                            let slot = Int(instruction.x)
                            stack.append(.restore(slot: slot, value: working[slot]))
                            working[slot] = position
                            stack.append(.explore(pc + 1))
                        case .assertion:
                            if let kind = Assertion(rawValue: UInt8(truncatingIfNeeded: instruction.x)),
                                Self.holds(kind, haystack, position)
                            {
                                stack.append(.explore(pc + 1))
                            }
                        case .byteRange, .byteSet, .match:
                            let base = pc * slotCount
                            if intoNext {
                                for slot in 0 ..< slotCount { next.slots[base + slot] = working[slot] }
                            } else {
                                for slot in 0 ..< slotCount { current.slots[base + slot] = working[slot] }
                            }
                    }
            }
        }
    }

    // MARK: Position tests

    private static func holds(_ assertion: Assertion, _ haystack: [UInt8], _ position: Int) -> Bool {
        let before = position > 0 ? haystack[position - 1] : nil
        let after = position < haystack.count ? haystack[position] : nil
        switch assertion {
            case .beginText: return before == nil
            case .endText: return after == nil
            case .beginLine: return before == nil || before == 0x0A
            case .endLine: return after == nil || after == 0x0A
            case .wordBoundary: return isWord(before) != isWord(after)
            case .notWordBoundary: return isWord(before) == isWord(after)
        }
    }

    private static func isWord(_ byte: UInt8?) -> Bool {
        guard let byte else { return false }
        return (0x30 ... 0x39).contains(byte) || (0x41 ... 0x5A).contains(byte) || (0x61 ... 0x7A).contains(byte)
            || byte == 0x5F
    }

    /// Whether a match may start at `position`: not in the middle of a valid multi-byte scalar.
    static func isBoundary(_ haystack: [UInt8], _ position: Int) -> Bool {
        guard position < haystack.count, (0x80 ... 0xBF).contains(haystack[position]) else { return true }
        for back in 1 ... 3 where position - back >= 0 {
            let width = Utf8.width(of: haystack, at: position - back)
            if width > back { return false }
        }
        return true
    }
}
