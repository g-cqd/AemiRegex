extension Pattern {
    /// The regular-expression syntax of a pattern.
    public enum Syntax: Equatable, Sendable {
        /// RE2's syntax (also Go's and Rust's), the default.
        case re2
        /// RFC 9485 (I-Regexp): a small interoperable subset, strictly checked, whose meaning is a whole-string match.
        case iRegexp
        /// I-Regexp as JSONPath implementations read it: `^` and `$` outside a class are anchors, as they are in the engines other
        /// implementations map I-Regexp to and in the JSONPath compliance suite. RFC 9485's grammar makes them ordinary characters
        /// (use ``iRegexp`` for that); every other rule is the same.
        case iRegexpWithAnchors
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
