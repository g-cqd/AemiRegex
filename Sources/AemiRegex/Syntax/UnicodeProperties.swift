/// Unicode properties by name, as Go's `regexp` reads `\p{…}`: general categories (with their long-name aliases), scripts, and the
/// special names `Any`, `Assigned`, `Ascii` and `Lc`. The data is generated (`GeneratedUnicodeTables`), so a pattern means the same on
/// every platform and nothing is scanned at run time (ADR-0009).
enum UnicodeProperties {
    private static let categoryCodes: [String] = GeneratedUnicodeTables.categoryCodes.split(separator: " ")
        .map(String.init)
    private static let scriptNames: [String] = GeneratedUnicodeTables.scriptNames.split(whereSeparator: \.isWhitespace)
        .map(String.init)

    /// The scripts, keyed by canonical name: `Old_Italic` is found as `Olditalic`.
    private static let scriptsByName: [String: Int] = {
        var result: [String: Int] = [:]
        for (index, name) in scriptNames.enumerated() { result[canonicalName(name)] = index }
        return result
    }()

    /// Go's normalisation of a property name: spaces, underscores and hyphens are dropped, the first letter is upper case and every
    /// other ASCII letter is lower case, so `gr_eek`, `GREEK` and `Greek` are one name.
    static func canonicalName(_ name: String) -> String {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(name.utf8.count)
        var first = true
        for byte in name.utf8 {
            if byte == 0x5F || byte == 0x2D || byte == 0x20 { continue }
            if first {
                bytes.append((0x61 ... 0x7A).contains(byte) ? byte - 32 : byte)
                first = false
            } else {
                bytes.append((0x41 ... 0x5A).contains(byte) ? byte + 32 : byte)
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Whether `name`, spelled exactly, is a general category RFC 9485 allows: a one-letter group or a two-letter category, not `Cs`.
    static func isGeneralCategory(_ name: String) -> Bool {
        name != "Cs" && (name.utf8.count == 1 ? "LMNPSZC".contains(name) : categoryCodes.contains(name) || name == "Cn")
    }

    /// The set a property name denotes, or `nil` when it names none.
    /// - Complexity: O(ranges in the set).
    static func set(named raw: String) -> ScalarSet? {
        let name = canonicalName(raw)
        switch name {
            case "Any": return ScalarSet(normalizing: [0 ... ScalarSet.maxScalar])
            case "Assigned": return unassigned().negated()
            case "Ascii": return ScalarSet(normalizing: [0 ... 0x7F])
            case "Lc": return union(["Lu", "Ll", "Lt"])
            default: break
        }
        if let category = category(name) { return category }
        if let target = aliases[name] { return target == "LC" ? union(["Lu", "Ll", "Lt"]) : category(target) }
        guard let index = scriptsByName[name] else { return nil }
        return ranges(GeneratedUnicodeTables.scriptData, GeneratedUnicodeTables.scriptOffsets, index)
    }

    /// The category aliases spelled exactly, `Uppercase_Letter` to `Lu`, for ECMAScript, which accepts no other spelling.
    private static let exactAliases: [String: String] = {
        var result: [String: String] = [:]
        for pair in GeneratedUnicodeTables.categoryAliases.split(whereSeparator: \.isWhitespace) {
            let parts = pair.split(separator: "=")
            if parts.count == 2 { result[String(parts[0])] = String(parts[1]) }
        }
        return result
    }()

    /// The same aliases keyed by canonical name: `Uppercase_Letter` is found as `Uppercaseletter`.
    private static let aliases: [String: String] = Dictionary(
        uniqueKeysWithValues: exactAliases.map { (canonicalName($0.key), $0.value) })

    /// The category with this code: a two-letter one (`Lu`), a one-letter group (`L`), `Cn`, or `LC` (cased letters). PCRE2 reads these.
    /// - Returns: The set, or `nil` when `code` is none of them (a long name is not a code).
    static func category(code: String) -> ScalarSet? {
        code == "LC" ? union(["Lu", "Ll", "Lt"]) : category(code)
    }

    /// The category spelled exactly as ECMAScript spells it: a code, or an exact long name such as `Uppercase_Letter`.
    static func exactCategory(_ name: String) -> ScalarSet? {
        if let set = category(code: name) { return set }
        return exactAliases[name].flatMap { category(code: $0) }
    }

    /// The one-letter groups and their members. `C` also holds every unassigned code point, added by ``category(_:)``.
    private static let groups: [String: [String]] = [
        // @dl:accept -- a table of constants: the rows are alike because they are data
        "L": ["Lu", "Ll", "Lt", "Lm", "Lo"], "M": ["Mn", "Mc", "Me"], "N": ["Nd", "Nl", "No"],
        "P": ["Pc", "Pd", "Ps", "Pe", "Pi", "Pf", "Po"], "S": ["Sm", "Sc", "Sk", "So"], "Z": ["Zs", "Zl", "Zp"],
        "C": ["Cc", "Cf", "Co", "Cs"]
    ]

    private static func category(_ name: String) -> ScalarSet? {
        if let members = groups[name] { return name == "C" ? union(members).union(unassigned()) : union(members) }
        if name == "Cn" { return unassigned() }
        guard let index = categoryCodes.firstIndex(of: name) else { return nil }
        return categoryRanges(index)
    }

    /// Every scalar value that is in none of the 29 listed categories: Go's `Cn`.
    private static func unassigned() -> ScalarSet {
        var listed: [ClosedRange<UInt32>] = []
        for index in 0 ..< categoryCodes.count {
            listed += categoryRanges(index).ranges
        }
        return ScalarSet(normalizing: listed).negated()
    }

    private static func union(_ codes: [String]) -> ScalarSet {
        var result = ScalarSet()
        for code in codes {
            guard let index = categoryCodes.firstIndex(of: code) else { continue }
            result = result.union(
                ranges(GeneratedUnicodeTables.categoryData, GeneratedUnicodeTables.categoryOffsets, index))
        }
        return result
    }

    private static func categoryRanges(_ index: Int) -> ScalarSet {
        ranges(GeneratedUnicodeTables.categoryData, GeneratedUnicodeTables.categoryOffsets, index)
    }

    /// The ranges of table `index` of a generated table, which stores each as an inclusive `lo, hi` pair.
    static func ranges(_ data: [UInt32], _ offsets: [Int], _ index: Int) -> ScalarSet {
        var result: [ClosedRange<UInt32>] = []
        result.reserveCapacity(offsets[index + 1] - offsets[index])
        for range in offsets[index] ..< offsets[index + 1] { result.append(data[2 * range] ... data[2 * range + 1]) }
        return ScalarSet(normalizing: result)
    }
}
