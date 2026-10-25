extension BacktrackingPattern {
    /// The flags a pattern is compiled with, as `i`, `m` and `s` are in ECMAScript and PCRE2.
    public struct Options: OptionSet, Sendable {
        public let rawValue: UInt8

        public init(rawValue: UInt8) { self.rawValue = rawValue }

        /// Letters match their other case (simple case folding).
        public static let ignoreCase = Options(rawValue: 1 << 0)
        /// `^` and `$` match at every line, not only at the ends of the text.
        public static let multiLine = Options(rawValue: 1 << 1)
        /// `.` also matches a line terminator.
        public static let dotAll = Options(rawValue: 1 << 2)
        /// PCRE2's `x`: white space and `#` comments in the pattern are ignored. ECMAScript has no such flag, so compiling with it there throws.
        public static let extended = Options(rawValue: 1 << 3)
        /// ECMAScript's `v` flag: `u` semantics plus set notation in classes (`[\\w--[a-c]]`, `[\\p{L}&&\\p{ASCII}]`, nested classes, `\\q{…}`). PCRE2 has no such flag, so
        /// compiling with it there throws. Properties of strings such as `\\p{RGI_Emoji}` are not supported.
        public static let unicodeSets = Options(rawValue: 1 << 4)
    }
}
