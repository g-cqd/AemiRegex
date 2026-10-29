internal import AemiUnicode

extension UnicodeScalarSet {
    /// `\n`, the one scalar `.` does not match by default.
    static let newline = UnicodeScalarSet(0x0A)
}
