extension Pattern {
    /// The regular-expression syntax of a pattern.
    public enum Syntax: Equatable, Sendable {
        /// RE2's syntax (also Go's and Rust's), the default.
        case re2
        /// RFC 9485 (I-Regexp): a small interoperable subset, strictly checked, whose meaning is a whole-string match.
        case iRegexp
    }

    /// Whether a match may be anywhere in the text, or must be the whole text.
    public enum Matching: Equatable, Sendable {
        case search
        case wholeString
    }

    /// Which engines may run. The Pike VM alone is the reference the DFA pipeline is tested against.
    enum Engine: Sendable {
        case automatic
        case pikeOnly
    }
}
