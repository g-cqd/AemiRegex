internal import AemiUnicode

/// Binary properties and Script_Extensions by name, from AemiUnicode's `UnicodeData` (node's Unicode 17 data, which ECMAScript patterns
/// are checked against; ADR-0013), and scripts by their four-letter codes. ECMAScript spells names exactly; PCRE2 ignores case, spaces
/// and underscores.
enum UnicodeBinaryProperties {
    /// Each binary property name and alias, spelled exactly, with the property's name.
    private static let binaryByName: [String: String] = {
        var result: [String: String] = [:]
        for name in UnicodeData.binaryPropertyNames { result[name] = name }
        for (alias, canonical) in UnicodeData.binaryPropertyAliases where result[canonical] != nil {
            result[alias] = canonical
        }
        return result
    }()

    /// Each script name and four-letter code, spelled exactly, with the script's long name.
    private static let scriptByName: [String: String] = {
        var result: [String: String] = [:]
        for name in UnicodeData.scriptNames { result[name] = name }
        for (code, name) in UnicodeData.scriptCodes { result[code] = name }
        return result
    }()

    /// The same names with case, spaces, underscores and hyphens ignored, as PCRE2 reads them.
    private static let looseBinaryByName = loosened(binaryByName)
    private static let looseScriptByName = loosened(scriptByName)

    private static func loosened(_ names: [String: String]) -> [String: String] {
        Dictionary(
            names.sorted { $0.key < $1.key }.map { (loose($0.key), $0.value) }, uniquingKeysWith: { first, _ in first })
    }

    /// `name` lower-cased with spaces, underscores and hyphens removed.
    static func loose(_ name: String) -> String {
        String(name.lowercased().filter { $0 != " " && $0 != "_" && $0 != "-" })
    }

    /// How a name is matched: ECMAScript spells names exactly, PCRE2 ignores case, spaces, underscores and hyphens.
    enum Spelling {
        case exact
        case loose
    }

    /// The binary property `name` names (`Alphabetic`, or its alias `Alpha`).
    static func binary(_ name: String, _ spelling: Spelling) -> UnicodeScalarSet? {
        let canonical = spelling == .exact ? binaryByName[name] : looseBinaryByName[loose(name)]
        return canonical.flatMap(UnicodeData.binaryProperty)
    }

    /// The long name of the script `name` names: a long name or a four-letter code.
    private static func script(named name: String, _ spelling: Spelling) -> String? {
        spelling == .exact ? scriptByName[name] : looseScriptByName[loose(name)]
    }

    /// The Script property of the script `name` names.
    static func script(_ name: String, _ spelling: Spelling) -> UnicodeScalarSet? {
        script(named: name, spelling).flatMap(UnicodeData.script)
    }

    /// The Script_Extensions of the script `name` names.
    static func scriptExtensions(_ name: String, _ spelling: Spelling) -> UnicodeScalarSet? {
        script(named: name, spelling).flatMap(UnicodeData.scriptExtensions)
    }
}
