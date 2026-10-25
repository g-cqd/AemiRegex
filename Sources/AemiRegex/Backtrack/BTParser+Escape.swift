extension BTParser {
    /// Parses the character escape at the backslash: a scalar (`\n`, `\x41`, `\u{1F600}`) or a set (`\d`, `\p{L}`).
    /// - Parameter inClass: Whether the escape is inside `[...]`, where `\b` is a backspace and `-` may be escaped.
    /// - Returns: What the escape stands for; the position is left after it.
    /// - Throws: ``PatternError`` for an escape the dialect does not define or one that is malformed.
    mutating func parseCharacterEscape(inClass: Bool) throws(PatternError) -> BTEscaped {
        let at = offset(position)
        position += 1
        guard let c = peek() else { throw .syntax(.unexpectedEnd, offset: offset(scalars.count)) }
        position += 1
        if let set = BTSets.perl(c, dialect, ignoreCase: flags.ignoreCase) { return .set(set) }
        switch c {
            case 0x74: return .scalar(0x09)
            case 0x6E: return .scalar(0x0A)
            case 0x72: return .scalar(0x0D)
            case 0x66: return .scalar(0x0C)
            case 0x76 where isECMAScript: return .scalar(0x0B)
            case 0x76: return .set(BTSets.verticalSpace)
            case 0x56 where !isECMAScript: return .set(BTSets.verticalSpace.negated())
            case 0x68 where !isECMAScript: return .set(BTSets.horizontalSpace)
            case 0x48 where !isECMAScript: return .set(BTSets.horizontalSpace.negated())
            case 0x61 where !isECMAScript: return .scalar(0x07)
            case 0x65 where !isECMAScript: return .scalar(0x1B)
            case 0x62 where inClass: return .scalar(0x08)
            case 0x30: return .scalar(try zeroEscape(at: at))
            case 0x31 ... 0x37 where !isECMAScript && inClass:
                position -= 1
                return .scalar(try octal(maxDigits: 3, at: at))
            case 0x63: return .scalar(try controlEscape(at: at))
            case 0x78: return .scalar(try hexEscape(at: at))
            case 0x75 where isECMAScript: return .scalar(try unicodeEscape(at: at))
            case 0x6F where !isECMAScript:
                guard peek() == 0x7B else { throw .syntax(.invalidEscape, offset: at) }
                position += 1
                return .scalar(try braced(radix: 8, allowSurrogates: true, at: at))
            case 0x70, 0x50: return try propertyEscape(negated: c == 0x50, at: at)
            default: return .scalar(try identityEscape(c, inClass: inClass, at: at))
        }
    }

    private func identityEscape(_ c: UInt32, inClass: Bool, at: Int) throws(PatternError) -> UInt32 {
        if isECMAScript {
            let syntax: [UInt32] = Array("^$\\.*+?()[]{}|/".unicodeScalars.map(\.value))
            guard syntax.contains(c) || (inClass && c == 0x2D) else { throw .syntax(.invalidEscape, offset: at) }
            return c
        }
        let isAlphanumeric = (0x30 ... 0x39).contains(c) || (0x41 ... 0x5A).contains(c) || (0x61 ... 0x7A).contains(c)
        guard !isAlphanumeric else { throw .syntax(.invalidEscape, offset: at) }
        return c
    }

    private mutating func zeroEscape(at: Int) throws(PatternError) -> UInt32 {
        if isECMAScript {
            if let next = peek(), (0x30 ... 0x39).contains(next) { throw .syntax(.invalidEscape, offset: at) }
            return 0
        }
        position -= 1
        return try octal(maxDigits: 3, at: at)
    }

    /// Reads up to `maxDigits` octal digits at the current position.
    private mutating func octal(maxDigits: Int, at: Int) throws(PatternError) -> UInt32 {
        var value: UInt32 = 0
        var count = 0
        while count < maxDigits, let digit = peek(), (0x30 ... 0x37).contains(digit) {
            value = value * 8 + (digit - 0x30)
            position += 1
            count += 1
        }
        guard value <= 0xFF else { throw .syntax(.invalidScalar, offset: at) }
        return value
    }

    private mutating func controlEscape(at: Int) throws(PatternError) -> UInt32 {
        guard let letter = peek() else { throw .syntax(.unexpectedEnd, offset: offset(scalars.count)) }
        let isLetter = (0x41 ... 0x5A).contains(letter) || (0x61 ... 0x7A).contains(letter)
        if isECMAScript {
            guard isLetter else { throw .syntax(.invalidEscape, offset: at) }
        } else {
            guard (0x20 ... 0x7E).contains(letter) else { throw .syntax(.invalidEscape, offset: at) }
        }
        position += 1
        let upper = (0x61 ... 0x7A).contains(letter) ? letter - 0x20 : letter
        return upper ^ 0x40
    }

    private mutating func hexEscape(at: Int) throws(PatternError) -> UInt32 {
        if !isECMAScript, peek() == 0x7B {
            position += 1
            return try braced(radix: 16, allowSurrogates: true, at: at)
        }
        var value: UInt32 = 0
        var count = 0
        while count < 2, let digit = peek().flatMap(Self.hexValue) {
            value = value * 16 + digit
            position += 1
            count += 1
        }
        if isECMAScript ? count != 2 : count == 0 { throw .syntax(.invalidEscape, offset: at) }
        return value
    }

    /// `\u{H+}` or `\uHHHH`, and a surrogate pair `\uD83D\uDE00` as the one scalar it encodes.
    private mutating func unicodeEscape(at: Int) throws(PatternError) -> UInt32 {
        if peek() == 0x7B {
            position += 1
            return try braced(radix: 16, allowSurrogates: true, at: at)
        }
        let high = try fourHex(at: at)
        guard (0xD800 ... 0xDBFF).contains(high), peek() == 0x5C, peek(1) == 0x75 else { return high }
        let saved = position
        position += 2
        if let low = try? fourHex(at: at), (0xDC00 ... 0xDFFF).contains(low) {
            return 0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00)
        }
        position = saved
        return high
    }

    private mutating func fourHex(at: Int) throws(PatternError) -> UInt32 {
        var value: UInt32 = 0
        for _ in 0 ..< 4 {
            guard let digit = peek().flatMap(Self.hexValue) else { throw .syntax(.invalidEscape, offset: at) }
            value = value * 16 + digit
            position += 1
        }
        return value
    }
}
