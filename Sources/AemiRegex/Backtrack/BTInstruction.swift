/// One step of a backtracking program. Jump offsets are relative to the instruction itself.
struct BTInstruction: Equatable, Sendable {
    enum Op: UInt8, Sendable {
        /// Consume the scalar `x`.
        case char
        /// Consume one scalar that is in set `x`.
        case set
        /// Continue at `pc + x`, and later (if that fails) at `pc + y`.
        case split
        /// Continue at `pc + x`.
        case jump
        /// Record the position in slot `x`.
        case save
        /// Continue only if ``BTAssertion`` `x` holds.
        case assertion
        /// Consume the text group `x` matched (`y == 1` ignores case).
        case backReference
        /// Start a look-around: `x == 1` is negative; `y` is the offset of the instruction after its ``lookEnd``.
        case lookStart
        /// End a look-around body (`x == 1` is negative).
        case lookEnd
        /// Start a group that is matched once and never re-entered.
        case atomicStart
        case atomicEnd
        /// Record the position in loop register slot `x`.
        case setRegister
        /// If the position equals register `x` (the iteration matched empty): fail when `y == 0`, otherwise continue at `pc + y`.
        case emptyCheck
        /// Unset the capture groups `x ..< y`.
        case resetCaptures
        /// Move the position back `x` scalars (PCRE2 look-behind); fails when the text before it is shorter.
        case stepBack
        /// Fail unless the position is where the enclosing look-around started (PCRE2 look-behind).
        case endAt
        /// Set the start of the reported match to the position (`\K`).
        case keep
        /// Never matches.
        case fail
        case match
    }

    var op: Op
    /// Whether a consuming instruction reads the text before the position (inside a look-behind).
    var backward = false
    var x: Int32 = 0
    var y: Int32 = 0

    init(_ op: Op, backward: Bool = false, _ x: Int = 0, _ y: Int = 0) {
        self.op = op
        self.backward = backward
        self.x = Int32(truncatingIfNeeded: x)
        self.y = Int32(truncatingIfNeeded: y)
    }
}
