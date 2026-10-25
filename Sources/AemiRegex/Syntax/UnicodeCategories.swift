/// Unicode general categories as scalar sets, built once from the standard library's property data.
///
/// This is an interim source (ADR-0008): the platform's Unicode version decides what each set contains, and the first use pays one pass
/// over all 1,114,112 scalar values. Roadmap 0005 decides whether generated tables replace it.
enum UnicodeCategories {
    /// The two-letter codes, indexed as in ``table``. `Cn` (unassigned) and `Cs` (surrogate) are included.
    private static let codes = Array(
        "Lu Ll Lt Lm Lo Mn Mc Me Nd Nl No Pc Pd Ps Pe Pi Pf Po Sm Sc Sk So Zs Zl Zp Cc Cf Cs Co Cn"
            .split(separator: " ").map(String.init))

    /// Whether `name` is allowed after `\p{` by RFC 9485: the seven groups and the two-letter categories except `Cs`.
    static func isXSDName(_ name: String) -> Bool {
        name != "Cs" && (name.count == 2 ? codes.contains(name) : ["L", "M", "N", "P", "S", "Z", "C"].contains(name))
    }

    private static func index(of category: Unicode.GeneralCategory) -> Int {
        switch category {
            // A 30-way table of constants: a switch is the fast form (this runs 1.1 million times on first use).
            // @dl:accept -- the table is the data; its rows are alike by nature
            case .uppercaseLetter: 0
            case .lowercaseLetter: 1
            case .titlecaseLetter: 2
            case .modifierLetter: 3
            case .otherLetter: 4
            case .nonspacingMark: 5
            case .spacingMark: 6
            case .enclosingMark: 7
            case .decimalNumber: 8
            case .letterNumber: 9
            case .otherNumber: 10
            case .connectorPunctuation: 11
            case .dashPunctuation: 12
            case .openPunctuation: 13
            case .closePunctuation: 14
            case .initialPunctuation: 15
            case .finalPunctuation: 16
            case .otherPunctuation: 17
            case .mathSymbol: 18
            case .currencySymbol: 19
            case .modifierSymbol: 20
            case .otherSymbol: 21
            case .spaceSeparator: 22
            case .lineSeparator: 23
            case .paragraphSeparator: 24
            case .control: 25
            case .format: 26
            case .surrogate: 27
            case .privateUse: 28
            case .unassigned: 29
            @unknown default: 29
        }
    }

    /// The ranges of each category, in the order of ``codes``. Built on first use; Swift initialises a static once and thread-safely.
    private static let table: [[ClosedRange<UInt32>]] = {
        var ranges = [[ClosedRange<UInt32>]](repeating: [], count: codes.count)
        var current = -1
        var start: UInt32 = 0
        for value in UInt32(0) ... ScalarSet.maxScalar {
            // `Unicode.Scalar` cannot hold a surrogate, which is category Cs.
            let category = Unicode.Scalar(value).map { index(of: $0.properties.generalCategory) } ?? 27
            if category != current {
                if current >= 0 { ranges[current].append(start ... value - 1) }
                current = category
                start = value
            }
        }
        ranges[current].append(start ... ScalarSet.maxScalar)
        return ranges
    }()

    /// The set for a category name: a two-letter code (`Lu`), or a one-letter group (`L`, `M`, `N`, `P`, `S`, `Z`, `C`).
    ///
    /// - Parameters:
    ///   - name: The category name.
    ///   - xsd: `true` for the XML Schema reading used by I-Regexp, where `C` and `Cn` include unassigned code points. `false` for RE2
    ///     and Go, where `C` is `Cc`, `Cf`, `Co` and `Cs`, and there is no `Cn`.
    /// - Returns: `nil` for a name that is not a general category in that reading.
    static func set(named name: String, xsd: Bool) -> ScalarSet? {
        let group: [String]
        switch name {
            // The category groups, one row each.
            // @dl:accept -- the table is the data; its rows are alike by nature
            case "L": group = ["Lu", "Ll", "Lt", "Lm", "Lo"]
            case "M": group = ["Mn", "Mc", "Me"]
            case "N": group = ["Nd", "Nl", "No"]
            case "P": group = ["Pc", "Pd", "Ps", "Pe", "Pi", "Pf", "Po"]
            case "S": group = ["Sm", "Sc", "Sk", "So"]
            case "Z": group = ["Zs", "Zl", "Zp"]
            case "C": group = xsd ? ["Cc", "Cf", "Co", "Cn"] : ["Cc", "Cf", "Cs", "Co"]
            case "Cn" where !xsd: return nil
            default: group = [name]
        }
        var ranges: [ClosedRange<UInt32>] = []
        for code in group {
            guard let position = codes.firstIndex(of: code) else { return nil }
            ranges += table[position]
        }
        return ScalarSet(normalizing: ranges)
    }
}
