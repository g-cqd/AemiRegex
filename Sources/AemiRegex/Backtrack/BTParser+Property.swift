extension BTParser {
    /// Parses what follows `\p` or `\P`: `{Name}`, `{Key=Value}` or, in PCRE2, a single letter.
    mutating func propertyEscape(negated: Bool, at: Int) throws(PatternError) -> ScalarSet {
        var invert = negated
        var name = ""
        if peek() == 0x7B {
            guard let close = scalars[position...].firstIndex(of: 0x7D) else {
                throw .syntax(.unexpectedEnd, offset: offset(scalars.count))
            }
            name = String(String.UnicodeScalarView(scalars[(position + 1) ..< close].compactMap(Unicode.Scalar.init)))
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
        guard let set = resolveProperty(name) else { throw .syntax(.unknownClassName, offset: at) }
        let folded = flags.ignoreCase ? set.folded() : set
        return invert ? folded.negated() : folded
    }

    /// The set for a property name. ECMAScript spells `General_Category=Lu`, `Script=Greek` or a bare category; PCRE2 also takes a bare
    /// script name and `L&`.
    private func resolveProperty(_ name: String) -> ScalarSet? {
        if let equals = name.firstIndex(of: "=") {
            let key = String(name[..<equals])
            let value = String(name[name.index(after: equals)...])
            switch key {
                case "General_Category", "gc":
                    return UnicodeProperties.isGeneralCategory(value) || value == "LC"
                        ? UnicodeProperties.set(named: value) : nil
                case "Script", "sc":
                    return UnicodeProperties.isGeneralCategory(value) ? nil : UnicodeProperties.set(named: value)
                default:
                    return nil
            }
        }
        if name == "L&" && !isECMAScript { return UnicodeProperties.set(named: "Lc") }
        if UnicodeProperties.isGeneralCategory(name) || name == "Any" || name == "Cn" {
            return UnicodeProperties.set(named: name)
        }
        if isECMAScript { return ["ASCII", "Assigned", "LC"].contains(name) ? UnicodeProperties.set(named: name) : nil }
        return UnicodeProperties.set(named: name)
    }
}
