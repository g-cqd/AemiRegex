internal import AemiUnicode

/// Unicode properties by name, as Go's `regexp` reads `\p{…}`: general categories (with their long-name aliases), scripts, and the
/// special names `Any`, `Assigned`, `Ascii` and `Lc`. The data is AemiUnicode's `UnicodeData`, generated tables of one Unicode version
/// (ADR-0009, ADR-0013); what is here is how Go spells the names.
enum UnicodeProperties {
    /// The scripts, keyed by canonical name: `Old_Italic` is found as `Olditalic`.
    private static let scriptsByName: [String: String] = {
        var result: [String: String] = [:]
        for name in UnicodeData.scriptNames { result[canonicalName(name)] = name }
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
        name != "Cs"
            && (name.utf8.count == 1
                ? "LMNPSZC".contains(name) : UnicodeData.generalCategoryCodes.contains(name) || name == "Cn")
    }

    /// The set a property name denotes, or `nil` when it names none.
    /// - Complexity: O(ranges in the set).
    static func set(named raw: String) -> UnicodeScalarSet? {
        let name = canonicalName(raw)
        switch name {
            case "Any": return UnicodeScalarSet(normalizing: [0 ... UnicodeScalarSet.maxScalar])
            case "Assigned": return UnicodeData.unassigned.negated()
            case "Ascii": return UnicodeScalarSet(normalizing: [0 ... 0x7F])
            case "Lc": return UnicodeData.generalCategory("LC")
            default: break
        }
        // A code (`Lu`, `L`, `Cn`); `LC` only through its alias `Cased_Letter`, as Go reads it.
        if name != "Lc", let category = UnicodeData.generalCategory(name) { return category }
        if let target = aliases[name] { return UnicodeData.generalCategory(target) }
        return scriptsByName[name].flatMap(UnicodeData.script)
    }

    /// The category aliases keyed by canonical name: `Uppercase_Letter` is found as `Uppercaseletter`.
    private static let aliases: [String: String] = Dictionary(
        uniqueKeysWithValues: UnicodeData.generalCategoryAliases.map { (canonicalName($0.key), $0.value) })

    /// The category with this code: a two-letter one (`Lu`), a one-letter group (`L`), `Cn`, or `LC` (cased letters). PCRE2 reads these.
    /// - Returns: The set, or `nil` when `code` is none of them (a long name is not a code).
    static func category(code: String) -> UnicodeScalarSet? {
        UnicodeData.generalCategory(code)
    }

    /// The category spelled exactly as ECMAScript spells it: a code, or an exact long name such as `Uppercase_Letter`.
    static func exactCategory(_ name: String) -> UnicodeScalarSet? {
        if let set = category(code: name) { return set }
        return UnicodeData.generalCategoryAliases[name].flatMap { category(code: $0) }
    }
}
