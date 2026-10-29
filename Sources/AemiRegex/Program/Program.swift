internal import AemiKernel

/// A compiled pattern: a flat instruction array, the byte sets that instructions refer to, and the capture layout.
struct Program: Sendable {
    var instructions: ContiguousArray<Instruction>
    var sets: ContiguousArray<ByteBitmap>
    /// Number of capture groups, not counting the whole match.
    var captureCount: Int
    var names: [String: Int]

    /// Two slots (start, end) for each group, including group 0.
    var slotCount: Int { 2 * (captureCount + 1) }
}
