/// One subroutine call in progress: where to go back to, and the slots as they were, so the call's captures can be undone on return.
struct BTCallFrame: Sendable {
    var group: Int
    var returnPC: Int
    /// The frame of the call that made this one, or -1.
    var parent: Int
    var snapshot: [Int]
    var depth: Int
    /// The position the call started at, to refuse a call that returns to the same group at the same place.
    var startPos: Int
}
