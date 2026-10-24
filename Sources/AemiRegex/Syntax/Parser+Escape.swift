extension Parser {
    enum Escape {
        case scalar(UInt32)
        case set(ScalarSet)
        case assertion(Assertion)
        /// `\Q`: the following scalars are literal up to `\E`.
        case quote
    }

    /// An escape outside a class: a scalar, a class, an assertion, or the start of a `\Q…\E` run.
    mutating func parseEscapeAtom() throws(PatternError) {
        switch try parseEscape(inClass: false) {
            case .scalar(let scalar): try emitLiteral(scalar)
            case .set(let set): try emitSet(set)
            case .assertion(let assertion): try emit([.assertion(assertion)], nullable: true)
            case .quote:
                while position < scalars.count {
                    if scalars[position] == 0x5C, peek(1) == 0x45 {
                        position += 2
                        return
                    }
                    try emitLiteral(scalars[position])
                    position += 1
                }
        }
    }

    /// Parses the escape at the current position (a backslash) and moves past it.
    mutating func parseEscape(inClass: Bool) throws(PatternError) -> Escape {
        let start = offset(position)
        position += 1
        guard let c = peek() else { throw .syntax(.unexpectedEnd, offset: start) }
        position += 1
        switch c {
            case 0x31 ... 0x37:
                guard let next = peek(), (0x30 ... 0x37).contains(next) else {
                    throw .syntax(.unsupported, offset: start)
                }
                return .scalar(octal(first: c))
            case 0x38, 0x39: throw .syntax(.invalidEscape, offset: start)
            case 0x30: return .scalar(octal(first: c))
            case 0x78: return .scalar(try hex(start: start))
            case 0x61: return .scalar(0x07)
            case 0x66: return .scalar(0x0C)
            case 0x74: return .scalar(0x09)
            case 0x6E: return .scalar(0x0A)
            case 0x72: return .scalar(0x0D)
            case 0x76: return .scalar(0x0B)
            case 0x64, 0x44, 0x73, 0x53, 0x77, 0x57:
                guard let set = ClassCatalog.perl(c) else { throw .syntax(.invalidEscape, offset: start) }
                return .set(set)
            case 0x62, 0x42, 0x41, 0x7A:
                guard !inClass else { throw .syntax(.invalidEscape, offset: start) }
                switch c {
                    case 0x62: return .assertion(.wordBoundary)
                    case 0x42: return .assertion(.notWordBoundary)
                    case 0x41: return .assertion(.beginText)
                    default: return .assertion(.endText)
                }
            case 0x70, 0x50: throw .syntax(.unsupported, offset: start)
            case 0x51:
                guard !inClass else { throw .syntax(.invalidEscape, offset: start) }
                return .quote
            default:
                guard c < 0x80, !Self.isAlphanumeric(c) else { throw .syntax(.invalidEscape, offset: start) }
                return .scalar(c)
        }
    }

    private static func isAlphanumeric(_ c: UInt32) -> Bool {
        (0x30 ... 0x39).contains(c) || (0x41 ... 0x5A).contains(c) || (0x61 ... 0x7A).contains(c)
    }

    /// An octal escape: the first digit was already consumed; up to two more follow.
    private mutating func octal(first: UInt32) -> UInt32 {
        var value = first - 0x30
        for _ in 0 ..< 2 {
            guard let next = peek(), (0x30 ... 0x37).contains(next) else { break }
            value = value * 8 + (next - 0x30)
            position += 1
        }
        return value
    }

    /// `\xHH` or `\x{H…}`, after the `x`.
    private mutating func hex(start: Int) throws(PatternError) -> UInt32 {
        if peek() == 0x7B {
            position += 1
            var value: UInt32 = 0
            var digits = 0
            while let c = peek(), c != 0x7D {
                guard let digit = Self.hexValue(c) else { throw .syntax(.invalidEscape, offset: start) }
                value = value * 16 + digit
                guard value <= ScalarSet.maxScalar else { throw .syntax(.invalidScalar, offset: start) }
                digits += 1
                position += 1
            }
            guard peek() == 0x7D, digits > 0 else { throw .syntax(.invalidEscape, offset: start) }
            position += 1
            guard !(0xD800 ... 0xDFFF).contains(value) else { throw .syntax(.invalidScalar, offset: start) }
            return value
        }
        guard let high = peek().flatMap(Self.hexValue), let low = peek(1).flatMap(Self.hexValue) else {
            throw .syntax(.invalidEscape, offset: start)
        }
        position += 2
        return high * 16 + low
    }

    private static func hexValue(_ c: UInt32) -> UInt32? {
        switch c {
            case 0x30 ... 0x39: c - 0x30
            case 0x41 ... 0x46: c - 0x41 + 10
            case 0x61 ... 0x66: c - 0x61 + 10
            default: nil
        }
    }
}
