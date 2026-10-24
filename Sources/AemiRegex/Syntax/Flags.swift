/// The inline flags `(?imsU)`. They apply from where they appear to the end of the enclosing group.
struct Flags: Equatable, Sendable {
    var ignoreCase = false
    var multiLine = false
    /// `.` also matches `\n`.
    var dotAll = false
    /// Swaps the meaning of greedy and lazy quantifiers.
    var swapGreed = false
}
