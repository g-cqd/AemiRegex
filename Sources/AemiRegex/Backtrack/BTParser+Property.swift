extension BTParser {
    /// Parses what follows `\p` or `\P`: `{Name}`, `{Key=Value}` or, in PCRE2, a single letter.
    /// - Returns: The set, already inverted for `\P` and `{^Name}`, and widened by case folding where the dialect does so.
    /// - Throws: ``PatternError`` with `.unknownClassName` for a name the dialect does not have, `.unsupported` for one this engine has no data for.
    mutating func propertyEscape(negated: Bool, at: Int) throws(PatternError) -> BTEscaped {
        var invert = negated
        var name = ""
        if peek() == 0x7B {
            guard let close = scalars[position...].firstIndex(of: 0x7D) else {
                throw .syntax(.unexpectedEnd, offset: offset(scalars.count))
            }
            name = text((position + 1) ..< close)
            position = close + 1
        } else if !isECMAScript, let letter = peek().flatMap(Unicode.Scalar.init) {
            name = String(letter)
            position += 1
        } else {
            throw .syntax(.invalidEscape, offset: at)
        }
        if !isECMAScript, name.hasPrefix("^") {
            invert.toggle()
            name.removeFirst()
        }
        if isECMAScript {
            guard let set = ecmaProperty(name) else { throw .syntax(.unknownClassName, offset: at) }
            // ECMAScript complements first and folds after, so `\P{Lowercase}` under `i` still matches `A`.
            let base = invert ? set.negated() : set
            return .set(flags.ignoreCase ? base.folded() : base)
        }
        let (set, cased) = try pcreProperty(name, at: at)
        // Caseless matching turns `\p{Lu}`, `\p{Ll}` and `\p{Lt}` into `\p{L&}`; no other property changes.
        let widened = cased && flags.ignoreCase
        let base = widened ? (UnicodeProperties.category(code: "LC") ?? set) : set
        let result = invert ? base.negated() : base
        return widened ? .set(result) : .fixedSet(result)
    }

    /// An ECMAScript property: `General_Category=Lu`, `Script=Greek`, `Script_Extensions=Greek` (and `gc`, `sc`, `scx`), or a bare general
    /// category or binary property. Names are exact.
    private func ecmaProperty(_ name: String) -> ScalarSet? {
        guard let equals = name.firstIndex(of: "=") else {
            return UnicodeProperties.exactCategory(name) ?? UnicodeBinaryProperties.binary(name, .exact)
        }
        let value = String(name[name.index(after: equals)...])
        switch name[..<equals] {
            case "General_Category", "gc": return UnicodeProperties.exactCategory(value)
            case "Script", "sc": return UnicodeBinaryProperties.script(value, .exact)
            case "Script_Extensions", "scx": return UnicodeBinaryProperties.scriptExtensions(value, .exact)
            default: return nil
        }
    }

    /// A PCRE2 property, names read loosely. A bare script name means Script_Extensions; `sc=` means Script.
    /// - Returns: The set, and whether caseless matching widens it (only the cased letters `Lu`, `Ll`, `Lt`, `L&`).
    private func pcreProperty(_ raw: String, at: Int) throws(PatternError) -> (ScalarSet, cased: Bool) {
        let separator = raw.firstIndex { $0 == "=" || $0 == ":" }
        if let separator {
            let key = UnicodeBinaryProperties.loose(String(raw[..<separator]))
            let value = String(raw[raw.index(after: separator)...])
            switch key {
                case "script", "sc":
                    guard let set = UnicodeBinaryProperties.script(value, .loose) else { break }
                    return (set, false)
                case "scriptextensions", "scx":
                    guard let set = UnicodeBinaryProperties.scriptExtensions(value, .loose) else { break }
                    return (set, false)
                case "bidiclass", "bc": throw .syntax(.unsupported, offset: at)
                default: break
            }
            throw .syntax(.unknownClassName, offset: at)
        }
        let key = UnicodeBinaryProperties.loose(raw)
        switch key {
            case "any": return (ScalarSet(normalizing: [0 ... ScalarSet.maxScalar]), false)
            case "l&", "lc": return (UnicodeProperties.category(code: "LC") ?? ScalarSet(), true)
            case "xan": return (letters.union(UnicodeProperties.category(code: "N") ?? ScalarSet()), false)
            case "xwd":
                return (
                    letters.union(UnicodeProperties.category(code: "N") ?? ScalarSet()).union(ScalarSet(0x5F)), false
                )
            case "xsp", "xps": return (Self.perlSpace, false)
            case "xuc": return (Self.universalCharacters, false)
            default: break
        }
        if let category = Self.category(loose: key) { return (category, ["lu", "ll", "lt"].contains(key)) }
        if key != "assigned", let set = UnicodeBinaryProperties.binary(raw, .loose) { return (set, false) }
        // A bare script name matches a character that has the script or lists it among its extensions.
        if let extensions = UnicodeBinaryProperties.scriptExtensions(raw, .loose) {
            return (extensions.union(UnicodeBinaryProperties.script(raw, .loose) ?? ScalarSet()), false)
        }
        throw .syntax(.unknownClassName, offset: at)
    }

    private var letters: ScalarSet { UnicodeProperties.category(code: "L") ?? ScalarSet() }

    /// PCRE2's `Xsp` and `Xps`: the characters Perl calls space.
    private static let perlSpace = BTSets.pcreSpace.union(UnicodeProperties.category(code: "Z") ?? ScalarSet())

    /// PCRE2's `Xuc`: the characters a universal character name may stand for.
    private static let universalCharacters = ScalarSet(
        normalizing: [0x24 ... 0x24, 0x40 ... 0x40, 0x60 ... 0x60, 0xA0 ... 0xD7FF, 0xE000 ... ScalarSet.maxScalar])

    /// A general category by its code with case ignored (`lu` is `Lu`), or `nil`: PCRE2 has no long names.
    private static func category(loose key: String) -> ScalarSet? {
        guard key.utf8.count <= 2, let first = key.first else { return nil }
        let code = String(first).uppercased() + key.dropFirst()
        return UnicodeProperties.category(code: code)
    }
}
