extension IRegexp.Translator {
    /// A bracketed class at `index`. Returns the index after its `]`.
    mutating func characterClass(at index: Int) throws(PatternError) -> Int {
        let open = offset(index)
        var cursor = index + 1
        output += "["
        if cursor < scalars.count, scalars[cursor] == 0x5E {
            // The RFC forbids "[^]": by the grammar it would be a positive class holding a caret.
            if cursor + 1 < scalars.count, scalars[cursor + 1] == 0x5D {
                throw .syntax(.invalidClassRange, offset: open)
            }
            output += "^"
            cursor += 1
        }
        if cursor < scalars.count, scalars[cursor] == 0x2D {
            output += "\\-"
            cursor += 1
        } else {
            cursor = try classItem(at: cursor, open: open)
        }
        while true {
            guard cursor < scalars.count else { throw .syntax(.unterminatedClass, offset: open) }
            if scalars[cursor] == 0x5D {
                output += "]"
                return cursor + 1
            }
            if scalars[cursor] == 0x2D, cursor + 1 < scalars.count, scalars[cursor + 1] == 0x5D {
                output += "\\-"
                cursor += 1
                continue
            }
            cursor = try classItem(at: cursor, open: open)
        }
    }

    /// One CCE1 of the ABNF: a category escape, a character, or a range of two characters.
    mutating func classItem(at index: Int, open: Int) throws(PatternError) -> Int {
        guard index < scalars.count else { throw .syntax(.unterminatedClass, offset: open) }
        if scalars[index] == 0x5C, index + 1 < scalars.count,
            scalars[index + 1] == 0x70 || scalars[index + 1] == 0x50
        {
            return try escape(at: index, inClass: true)
        }
        guard let (low, afterLow) = try classCharacter(at: index) else {
            throw .syntax(.invalidCharacter, offset: offset(index))
        }
        if afterLow + 1 < scalars.count, scalars[afterLow] == 0x2D, scalars[afterLow + 1] != 0x5D {
            guard let (high, afterHigh) = try classCharacter(at: afterLow + 1), high >= low else {
                throw .syntax(.invalidClassRange, offset: offset(index))
            }
            appendLiteral(low, inClass: true)
            output += "-"
            appendLiteral(high, inClass: true)
            return afterHigh
        }
        appendLiteral(low, inClass: true)
        return afterLow
    }

    /// CCchar at `index`: the scalar and the index after it, or `nil` when none starts there. An escape that is not a SingleCharEsc
    /// is an error, not `nil`, so that `[\d]` is reported as an invalid escape.
    func classCharacter(at index: Int) throws(PatternError) -> (UInt32, Int)? {
        guard index < scalars.count else { return nil }
        let c = scalars[index]
        if c == 0x5C {
            guard index + 1 < scalars.count else { throw .syntax(.unexpectedEnd, offset: offset(index)) }
            guard let literal = Self.singleEscape(scalars[index + 1]) else {
                if scalars[index + 1] == 0x70 || scalars[index + 1] == 0x50 { return nil }
                throw .syntax(.invalidEscape, offset: offset(index))
            }
            return (literal, index + 2)
        }
        return Self.isClassChar(c) ? (c, index + 1) : nil
    }
}
