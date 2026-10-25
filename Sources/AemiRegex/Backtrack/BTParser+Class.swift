extension BTParser {
    /// Parses `[...]` at the current position and adds the set it denotes.
    mutating func parseClass() throws(PatternError) {
        let open = offset(position)
        position += 1
        let negated = peek() == 0x5E
        if negated { position += 1 }
        var members: [ClosedRange<UInt32>] = []
        var first = true
        while true {
            guard let c = peek() else { throw .syntax(.unterminatedClass, offset: open) }
            if c == 0x5D, !(first && !isECMAScript) {
                position += 1
                break
            }
            first = false
            let low = try classAtom()
            if peek() == 0x2D, let after = peek(1), after != 0x5D {
                position += 1
                let high = try classAtom()
                switch (low, high) {
                    case (.scalar(let a), .scalar(let b)):
                        guard a <= b else { throw .syntax(.invalidClassRange, offset: open) }
                        members.append(a ... b)
                    default:
                        throw .syntax(.invalidClassRange, offset: open)
                }
            } else {
                append(low, to: &members)
            }
        }
        var set = ScalarSet(normalizing: members)
        if flags.ignoreCase { set = set.folded() }
        try addSet(negated ? set.negated() : set)
    }

    private func append(_ atom: BTEscaped, to members: inout [ClosedRange<UInt32>]) {
        switch atom {
            case .scalar(let scalar): members.append(scalar ... scalar)
            case .set(let set): members += set.ranges
        }
    }

    private mutating func classAtom() throws(PatternError) -> BTEscaped {
        guard let c = peek() else { throw .syntax(.unterminatedClass, offset: offset(scalars.count)) }
        if c == 0x5C {
            if !isECMAScript, peek(1) == 0x51 {
                throw .syntax(.unsupported, offset: offset(position))
            }
            return try parseCharacterEscape(inClass: true)
        }
        if c == 0x5B, !isECMAScript, peek(1) == 0x3A, let posix = try posixClass() { return .set(posix) }
        position += 1
        return .scalar(c)
    }

    /// `[:alpha:]` inside a PCRE2 class, or `nil` when the text is not one.
    private mutating func posixClass() throws(PatternError) -> ScalarSet? {
        var end = position + 2
        while end + 1 < scalars.count, scalars[end] != 0x3A, scalars[end] != 0x5D { end += 1 }
        guard end + 1 < scalars.count, scalars[end] == 0x3A, scalars[end + 1] == 0x5D else { return nil }
        var name = String(String.UnicodeScalarView(scalars[(position + 2) ..< end].compactMap(Unicode.Scalar.init)))
        let negated = name.hasPrefix("^")
        if negated { name.removeFirst() }
        guard let set = ClassCatalog.posix(name) else { throw .syntax(.unknownClassName, offset: offset(position)) }
        position = end + 2
        return negated ? set.negated() : set
    }
}
