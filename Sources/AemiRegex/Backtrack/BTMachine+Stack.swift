extension BTMachine {
    // MARK: Stack

    mutating func push(_ tag: BTEntry.Tag, _ a: Int, _ b: Int) throws(BacktrackError) {
        guard stack.count < budget.maxStackEntries else { throw .budgetExceeded(.stack) }
        stack.append(BTEntry(tag: tag, a: a, b: b))
    }

    mutating func write(slot: Int, _ value: Int) throws(BacktrackError) {
        try push(.restore, slot, slots[slot])
        slots[slot] = value
    }

    mutating func reset(groups: Range<Int>) throws(BacktrackError) {
        for group in groups {
            for slot in [2 * group, 2 * group + 1] where slots[slot] >= 0 { try write(slot: slot, -1) }
        }
    }

    /// Resumes the most recent choice, undoing what was done since. Returns `false` when none is left.
    mutating func backtrack(_ pc: inout Int, _ pos: inout Int) -> Bool {
        while let entry = stack.popLast() {
            switch entry.tag {
                case .choice:
                    pc = entry.a
                    pos = entry.b
                    return true
                case .restore, .callEnter, .callExit: revert(entry)
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
    mutating func close(_ mark: Int) {
        var write = mark + 1
        for read in (mark + 1) ..< stack.count where Self.survivesClosing(stack[read].tag) {
            stack[write] = stack[read]
            write += 1
        }
        stack.removeSubrange(write...)
        stack[mark].tag = .inert
    }

    /// Takes back everything done since `mark`, the mark included.
    mutating func undo(to mark: Int) {
        while stack.count > mark {
            let entry = stack.removeLast()
            revert(entry)
        }
    }

    /// Whether a record stays when the atomic group or look-around it sits in ends: undo records do, choice points do not.
    private static func survivesClosing(_ tag: BTEntry.Tag) -> Bool {
        switch tag {
            case .restore, .inert, .callEnter, .callExit: true
            default: false
        }
    }

    /// Takes back what an undo record recorded.
    mutating func revert(_ entry: BTEntry) {
        switch entry.tag {
            case .restore: slots[entry.a] = entry.b
            case .callEnter:
                currentFrame = entry.a
                callFrames.removeLast()
            case .callExit: currentFrame = entry.a
            default: break
        }
    }
}
