/// Binary properties and Script_Extensions by name, from `GeneratedPropertyTables` (node's Unicode 17 data, which ECMAScript patterns are
/// checked against), and scripts by their four-letter codes. ECMAScript spells names exactly; PCRE2 ignores case, spaces and underscores.
enum UnicodeBinaryProperties {
    private static let binaryNames: [String] = GeneratedPropertyTables.binaryNames.split(whereSeparator: \.isWhitespace)
        .map(String.init)
    private static let scriptNames: [String] = GeneratedUnicodeTables.scriptNames.split(whereSeparator: \.isWhitespace)
        .map(String.init)

    private static func pairs(_ text: String) -> [(String, String)] {
        text.split(whereSeparator: \.isWhitespace)
            .compactMap { pair in
                let parts = pair.split(separator: "=")
                return parts.count == 2 ? (String(parts[0]), String(parts[1])) : nil
            }
    }

    /// Each binary property name and alias, spelled exactly, with the index of its table.
    private static let binaryIndex: [String: Int] = {
        var result: [String: Int] = [:]
        for (index, name) in binaryNames.enumerated() { result[name] = index }
        for (alias, canonical) in pairs(GeneratedPropertyTables.binaryAliases) {
            if let index = result[canonical] { result[alias] = index }
        }
        return result
    }()

    /// Each script name and four-letter code, spelled exactly, with the script's long name.
    private static let scriptByName: [String: String] = {
        var result: [String: String] = [:]
        for name in scriptNames { result[name] = name }
        for (code, name) in pairs(GeneratedPropertyTables.scriptCodes) { result[code] = name }
        return result
    }()

    /// The same names with case, spaces, underscores and hyphens ignored, as PCRE2 reads them.
    private static let looseBinaryIndex = loosened(binaryIndex)
    private static let looseScriptByName = loosened(scriptByName)

    private static func loosened<Value>(_ names: [String: Value]) -> [String: Value] {
        Dictionary(names.map { (loose($0.key), $0.value) }, uniquingKeysWith: { first, _ in first })
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
    static func binary(_ name: String, _ spelling: Spelling) -> ScalarSet? {
        let index = spelling == .exact ? binaryIndex[name] : looseBinaryIndex[loose(name)]
        return index.map(binarySet)
    }

    /// The long name of the script `name` names: a long name or a four-letter code.
    private static func script(named name: String, _ spelling: Spelling) -> String? {
        spelling == .exact ? scriptByName[name] : looseScriptByName[loose(name)]
    }

    /// The Script property of the script `name` names.
    static func script(_ name: String, _ spelling: Spelling) -> ScalarSet? {
        script(named: name, spelling).flatMap { UnicodeProperties.set(named: $0) }
    }

    /// The Script_Extensions of the script `name` names.
    static func scriptExtensions(_ name: String, _ spelling: Spelling) -> ScalarSet? {
        script(named: name, spelling).flatMap(extensions)
    }

    private static func extensions(_ script: String) -> ScalarSet? {
        scriptNames.firstIndex(of: script)
            .map {
                UnicodeProperties.ranges(
                    GeneratedPropertyTables.scriptExtensionData, GeneratedPropertyTables.scriptExtensionOffsets, $0)
            }
    }

    private static func binarySet(_ index: Int) -> ScalarSet {
        UnicodeProperties.ranges(GeneratedPropertyTables.binaryData, GeneratedPropertyTables.binaryOffsets, index)
    }
}
