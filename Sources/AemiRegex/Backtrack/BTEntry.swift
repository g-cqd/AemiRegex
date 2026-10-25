/// One record on the backtracking stack: a choice to resume, an undo for a slot, or the mark of an atomic group or look-around.
struct BTEntry: Sendable {
    enum Tag: UInt8, Sendable {
        /// Resume at program counter `a` with position `b`.
        case choice
        /// Set slot `a` back to `b`.
        case restore
        /// An atomic group that is still being matched.
        case atomicOpen
        /// A positive look-around being matched; `b` is the position to return to.
        case lookPositive
        /// A negative look-around being matched; if its body fails, resume at `a` with position `b`.
        case lookNegative
        /// A finished atomic group or look-around: nothing to do when it is popped.
        case inert
    }

    var tag: Tag
    var a: Int
    var b: Int
}
