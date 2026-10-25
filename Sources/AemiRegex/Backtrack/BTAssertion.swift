/// A zero-width condition of the backtracking engine. The dialect decides what a line terminator is when the machine evaluates it.
enum BTAssertion: Int32, Sendable {
    case beginText
    /// The end of the text only (`\z`, and `$` in ECMAScript).
    case endText
    /// The end of the text, or before a final line feed (`\Z`, and `$` in PCRE2).
    case endTextBeforeFinalNewline
    case beginLine
    case endLine
    case wordBoundary
    case notWordBoundary
}
