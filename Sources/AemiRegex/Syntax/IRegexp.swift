/// I-Regexp (RFC 9485): a strict check of the RFC's grammar and its translation to RE2 syntax, in one pass without recursion.
///
/// The translation is the RFC's own (section 5.4) with one correction: `.` outside a class becomes `[^\n\r]`, and `^` and `$` are
/// escaped. The RFC's text does not escape them, but its grammar makes them ordinary characters (as XSD does) and RE2 would read them as
/// anchors. Groups become non-capturing: I-Regexp has no captures. Whole-string matching is applied by the caller, at the program level.
///
/// Everything the grammar and the semantics allow us to check is checked here, with offsets in the text the caller wrote: a reversed
/// range, a repeat count out of order or over the limit, a category name outside the RFC's list. What the RE2 parser sees afterwards can
/// only fail on a limit (program size).
enum IRegexp {
    /// The RE2 source for `pattern`.
    /// - Throws: ``PatternError/syntax(_:offset:)`` with a byte offset in `pattern`, or a limit.
    /// - Complexity: O(pattern length); stack use is bounded by the nesting limit.
    static func translate(_ pattern: String, limits: Pattern.Limits) throws(PatternError) -> String {
        guard pattern.utf8.count <= limits.maxPatternBytes else { throw .limit(.patternLength) }
        var translator = Translator(pattern, limits: limits)
        try translator.run()
        return translator.output
    }
}
