extension BTMachine {
    /// Starts a subroutine call to `group` (0 is the whole pattern).
    ///
    /// The frame keeps a copy of the slots, so the call's captures can be undone when it returns, as PCRE2 does. Backtracking over the call
    /// drops the frame again.
    /// - Returns: `false` when the group is already being called at this position: the recursion could not make progress, so this path
    ///   fails, as it does in Perl.
    /// - Throws: ``BacktrackError`` when calls nest deeper than the budget allows.
    mutating func enterCall(group: Int, returnPC: Int, pos: Int) throws(BacktrackError) -> Bool {
        let depth = currentFrame >= 0 ? callFrames[currentFrame].depth + 1 : 1
        guard depth <= budget.maxRecursionDepth else { throw .budgetExceeded(.recursion) }
        guard callFrames.count < budget.maxStackEntries / 8 else { throw .budgetExceeded(.stack) }
        var ancestor = currentFrame
        while ancestor >= 0 {
            if callFrames[ancestor].group == group, callFrames[ancestor].startPos == pos { return false }
            ancestor = callFrames[ancestor].parent
        }
        try push(.callEnter, currentFrame, 0)
        callFrames.append(
            BTCallFrame(
                group: group, returnPC: returnPC, parent: currentFrame, snapshot: slots, depth: depth, startPos: pos))
        currentFrame = callFrames.count - 1
        return true
    }

    /// Ends the innermost call if it is a call to `group`: the slots go back to what they were at the call.
    /// - Returns: The instruction to continue at, or `nil` when no call to `group` is open.
    mutating func returnFromCall(group: Int) throws(BacktrackError) -> Int? {
        guard currentFrame >= 0, callFrames[currentFrame].group == group else { return nil }
        let frame = callFrames[currentFrame]
        for slot in slots.indices where slots[slot] != frame.snapshot[slot] {
            try write(slot: slot, frame.snapshot[slot])
        }
        try push(.callExit, currentFrame, 0)
        currentFrame = frame.parent
        return frame.returnPC
    }
}
