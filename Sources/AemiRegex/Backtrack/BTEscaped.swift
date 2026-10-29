internal import AemiUnicode

/// What a character escape such as `\n` or `\d` stands for.
enum BTEscaped: Equatable {
    case scalar(UInt32)
    case set(UnicodeScalarSet)
    /// A set that case-insensitive matching does not widen: PCRE2's `\p{Greek}` is the same under `i`.
    case fixedSet(UnicodeScalarSet)
}
