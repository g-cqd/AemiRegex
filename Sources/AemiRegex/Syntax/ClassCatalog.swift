internal import AemiUnicode

/// The named character classes: Perl (`\d \s \w`) and POSIX (`[:alpha:]`), as RE2 defines them (ASCII only).
enum ClassCatalog {
    static let digit = UnicodeScalarSet(normalizing: [0x30 ... 0x39])
    static let space = UnicodeScalarSet(normalizing: [0x09 ... 0x0A, 0x0C ... 0x0D, 0x20 ... 0x20])
    static let word = UnicodeScalarSet(normalizing: [0x30 ... 0x39, 0x41 ... 0x5A, 0x5F ... 0x5F, 0x61 ... 0x7A])

    /// The class for a Perl escape letter, as the positive set and whether the letter negates it (`\D` is `\d`, negated), or `nil`.
    /// Negation comes last so that case folding can be applied to the positive set first, as Go does.
    static func perl(_ letter: UInt32) -> (set: UnicodeScalarSet, negated: Bool)? {
        switch letter {
            case 0x64: (digit, false)
            case 0x44: (digit, true)
            case 0x73: (space, false)
            case 0x53: (space, true)
            case 0x77: (word, false)
            case 0x57: (word, true)
            default: nil
        }
    }

    private static let posixRanges: [String: [ClosedRange<UInt32>]] = [
        "alnum": [0x30 ... 0x39, 0x41 ... 0x5A, 0x61 ... 0x7A],
        "alpha": [0x41 ... 0x5A, 0x61 ... 0x7A],
        "ascii": [0x00 ... 0x7F],
        "blank": [0x09 ... 0x09, 0x20 ... 0x20],
        "cntrl": [0x00 ... 0x1F, 0x7F ... 0x7F],
        "digit": [0x30 ... 0x39],
        "graph": [0x21 ... 0x7E],
        "lower": [0x61 ... 0x7A],
        "print": [0x20 ... 0x7E],
        "punct": [0x21 ... 0x2F, 0x3A ... 0x40, 0x5B ... 0x60, 0x7B ... 0x7E],
        "space": [0x09 ... 0x0D, 0x20 ... 0x20],
        "upper": [0x41 ... 0x5A],
        "word": [0x30 ... 0x39, 0x41 ... 0x5A, 0x5F ... 0x5F, 0x61 ... 0x7A],
        "xdigit": [0x30 ... 0x39, 0x41 ... 0x46, 0x61 ... 0x66]
    ]

    /// The class for a POSIX name such as `alpha`, or `nil` for an unknown name.
    static func posix(_ name: String) -> UnicodeScalarSet? {
        posixRanges[name].map { UnicodeScalarSet(normalizing: $0) }
    }
}
