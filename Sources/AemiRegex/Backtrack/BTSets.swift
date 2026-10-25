/// The named character sets of the Perl family, as each dialect defines them.
enum BTSets {
    static let digit = ScalarSet(normalizing: [0x30 ... 0x39])
    static let word = ClassCatalog.word
    /// ECMAScript's white space and line terminators (`\s`).
    static let ecmaSpace = ScalarSet(
        normalizing: [
            // @dl:accept -- a table of constants: the rows are alike because they are data
            0x09 ... 0x0D, 0x20 ... 0x20, 0xA0 ... 0xA0, 0x1680 ... 0x1680, 0x2000 ... 0x200A, 0x2028 ... 0x2029,
            0x202F ... 0x202F, 0x205F ... 0x205F, 0x3000 ... 0x3000, 0xFEFF ... 0xFEFF
        ])
    /// PCRE2's `\s` without UCP: space, and the controls `\t \n \v \f \r`.
    static let pcreSpace = ScalarSet(normalizing: [0x09 ... 0x0D, 0x20 ... 0x20])
    /// PCRE2's `\h`.
    static let horizontalSpace = ScalarSet(
        normalizing: [
            // @dl:accept -- a table of constants: the rows are alike because they are data
            0x09 ... 0x09, 0x20 ... 0x20, 0xA0 ... 0xA0, 0x1680 ... 0x1680, 0x180E ... 0x180E, 0x2000 ... 0x200A,
            0x202F ... 0x202F, 0x205F ... 0x205F, 0x3000 ... 0x3000
        ])
    /// PCRE2's `\v`, and the line breaks `\R` takes besides `\r\n`.
    static let verticalSpace = ScalarSet(normalizing: [0x0A ... 0x0D, 0x85 ... 0x85, 0x2028 ... 0x2029])

    /// What ends a line for `.`, `^` and `$`.
    static func lineTerminators(_ dialect: BacktrackingPattern.Dialect) -> ScalarSet {
        switch dialect {
            case .ecmaScript: ScalarSet(normalizing: [0x0A ... 0x0A, 0x0D ... 0x0D, 0x2028 ... 0x2029])
            case .pcre2: ScalarSet.newline
        }
    }

    /// ECMAScript's `\w` with `i`: the two characters that fold to `s` and `k`.
    static let ecmaFoldedWord = word.union(ScalarSet(normalizing: [0x17F ... 0x17F, 0x212A ... 0x212A]))

    /// The set for `\d \D \s \S \w \W`, or `nil` for another letter.
    static func perl(_ letter: UInt32, _ dialect: BacktrackingPattern.Dialect, ignoreCase: Bool) -> ScalarSet? {
        let base: ScalarSet
        switch letter | 0x20 {
            case 0x64: base = digit
            case 0x77: base = dialect == .ecmaScript && ignoreCase ? ecmaFoldedWord : word
            case 0x73: base = dialect == .ecmaScript ? ecmaSpace : pcreSpace
            default: return nil
        }
        return letter < 0x61 ? base.negated() : base
    }
}
