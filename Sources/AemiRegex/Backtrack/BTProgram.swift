/// A compiled backtracking program: the instructions, the character sets they test, and the slot layout.
struct BTProgram: Sendable {
    var code: ContiguousArray<BTInstruction>
    var sets: [CharSet]
    var captureCount: Int
    /// Loop registers, stored after the capture slots.
    var registerCount: Int
    var dialect: BacktrackingPattern.Dialect

    /// Two slots for each group including group 0, then the loop registers.
    var slotCount: Int { 2 * (captureCount + 1) + registerCount }
}
