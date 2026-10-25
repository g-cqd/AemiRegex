/// The inline flags in force at a point of a pattern. They end with the group that set them.
struct BTFlags: Equatable, Sendable {
    var ignoreCase = false
    var multiLine = false
    /// `.` also matches a line terminator.
    var dotAll = false
    /// PCRE2's `x`: white space and `#` comments in the pattern are ignored.
    var extended = false
    /// PCRE2's `n`: plain parentheses do not capture.
    var noAutoCapture = false
}
