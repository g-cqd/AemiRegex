internal import AemiUnicode

/// A pattern decoded into scalars with a read position: what the RE2 parser and the backtracker's parser share.
protocol PatternCursor {
    var scalars: [UInt32] { get }
    /// `offsets[i]` is the UTF-8 offset of `scalars[i]`; the last entry is the pattern's length in bytes.
    var offsets: [Int] { get }
    var position: Int { get set }
    var limits: Pattern.Limits { get }
    /// The capture groups opened so far.
    var captureCount: Int { get set }
    var names: [String: Int] { get set }
}

extension PatternCursor {
    /// The byte offset of scalar `index`, for errors; an index past the end gives the pattern's length.
    func offset(_ index: Int) -> Int { offsets[min(index, offsets.count - 1)] }

    /// The scalar `delta` places after the position, or `nil` past the end.
    func peek(_ delta: Int = 0) -> UInt32? {
        let index = position + delta
        return index < scalars.count ? scalars[index] : nil
    }

    /// The pattern text in `range`, as a string.
    func text(_ range: Range<Int>) -> String {
        var result = ""
        for scalar in scalars[range] { result.unicodeScalars.append(Unicode.Scalar(scalar) ?? "_") }
        return result
    }

    static func hexValue(_ c: UInt32) -> UInt32? {
        switch c {
            case 0x30 ... 0x39: c - 0x30
            case 0x41 ... 0x46: c - 0x41 + 10
            case 0x61 ... 0x66: c - 0x61 + 10
            default: nil
        }
    }

    /// Reads decimal digits, saturating so that a long run of digits cannot overflow.
    func number(at index: inout Int) -> Int? {
        var value: Int?
        while index < scalars.count, (0x30 ... 0x39).contains(scalars[index]) {
            value = Swift.min((value ?? 0) * 10 + Int(scalars[index] - 0x30), 1_000_000)
            index += 1
        }
        return value
    }

    /// Parses `{n}`, `{n,}` or `{n,m}` at the position, or returns `nil` when the text is not a repetition, so `{` is a literal.
    /// - Parameters:
    ///   - spaces: Whether spaces may appear inside the braces (PCRE2).
    ///   - openMinimum: Whether `{,m}` means `{0,m}` (PCRE2).
    /// - Returns: The bounds (`max == nil` is unbounded) and how many scalars the quantifier uses.
    /// - Throws: ``PatternError`` when the bounds are out of order or over ``Pattern/Limits/maxRepetition``.
    func braces(spaces: Bool, openMinimum: Bool) throws(PatternError) -> (min: Int, max: Int?, length: Int)? {
        var index = position + 1
        func skip() { while spaces, index < scalars.count, scalars[index] == 0x20 { index += 1 } }
        skip()
        var minimum = number(at: &index)
        skip()
        var maximum = minimum
        if index < scalars.count, scalars[index] == 0x2C {
            index += 1
            skip()
            maximum = number(at: &index)
            skip()
            if openMinimum, minimum == nil, maximum != nil { minimum = 0 }
        }
        guard let minimum, index < scalars.count, scalars[index] == 0x7D else { return nil }
        if let maximum, maximum < minimum { throw .syntax(.invalidRepetition, offset: offset(position)) }
        guard minimum <= limits.maxRepetition, (maximum ?? 0) <= limits.maxRepetition else {
            throw .limit(.repetitionCount)
        }
        return (minimum, maximum, index + 1 - position)
    }

    /// Reads a group name from `start` up to `close`, checking each scalar with `allowed(scalar, isFirst)`.
    /// - Returns: The name and the index of `close`.
    /// - Throws: ``PatternError`` with `.invalidGroupName` when the name is empty, has a scalar that is not allowed, or is unterminated.
    func name(
        from start: Int, until close: UInt32, allowing allowed: (UInt32, Bool) -> Bool
    ) throws(PatternError) -> (name: String, end: Int) {
        var end = start
        while end < scalars.count, scalars[end] != close {
            guard allowed(scalars[end], end == start) else { throw .syntax(.invalidGroupName, offset: offset(end)) }
            end += 1
        }
        guard end < scalars.count, end > start else { throw .syntax(.invalidGroupName, offset: offset(start)) }
        return (text(start ..< end), end)
    }

    /// Reads `H+}` after an opening brace as a number in `radix`.
    /// - Parameters:
    ///   - radix: The base of the digits, 8 or 16.
    ///   - allowSurrogates: Whether `D800 ... DFFF` is a valid value.
    ///   - at: The byte offset to report an error at.
    /// - Returns: The value; the position is left after the closing brace.
    /// - Throws: ``PatternError`` when a digit is missing or wrong, or the value is not a scalar value.
    mutating func braced(radix: UInt32, allowSurrogates: Bool, at: Int) throws(PatternError) -> UInt32 {
        var value: UInt32 = 0
        var count = 0
        while let c = peek(), c != 0x7D {
            guard let digit = Self.hexValue(c), digit < radix else { throw .syntax(.invalidEscape, offset: at) }
            value = value * radix + digit
            guard value <= UnicodeScalarSet.maxScalar else { throw .syntax(.invalidScalar, offset: at) }
            position += 1
            count += 1
        }
        guard peek() == 0x7D, count > 0 else { throw .syntax(.invalidEscape, offset: at) }
        position += 1
        guard allowSurrogates || !(0xD800 ... 0xDFFF).contains(value) else { throw .syntax(.invalidScalar, offset: at) }
        return value
    }

    /// Scans inline flag letters, `i`, `m-s` and the like, from `start` (the scalar after `(?`) up to a scalar in `closers`.
    /// - Parameters:
    ///   - start: The index of the first flag letter.
    ///   - closers: The scalars that end the flags (`)` and `:`).
    ///   - allowEmptyNegation: Whether a `-` with no flag after it is accepted (PCRE2 does, RE2 and ECMAScript do not).
    ///   - apply: Records one flag letter, given whether a `-` has turned it off, and says whether the letter is a flag at all.
    /// - Returns: The index of the closer, the closer, and whether any flag letter was seen.
    /// - Throws: ``PatternError`` with `.invalidFlag` for an unknown letter, a second `-`, or a rejected empty negation.
    func scanFlags(
        from start: Int, closers: [UInt32], allowEmptyNegation: Bool = false, apply: (UInt32, Bool) -> Bool
    ) throws(PatternError) -> (end: Int, closer: UInt32, sawFlag: Bool) {
        var negating = false
        var sawFlag = false
        var sawAny = false
        var index = start
        while true {
            guard index < scalars.count else { throw .syntax(.unexpectedEnd, offset: offset(scalars.count)) }
            let c = scalars[index]
            if closers.contains(c) {
                if negating, !sawFlag, !allowEmptyNegation { throw .syntax(.invalidFlag, offset: offset(index)) }
                return (index, c, sawAny)
            }
            if c == 0x2D {
                guard !negating else { throw .syntax(.invalidFlag, offset: offset(index)) }
                negating = true
                sawFlag = false
            } else if apply(c, negating) {
                sawFlag = true
                sawAny = true
            } else {
                throw .syntax(.invalidFlag, offset: offset(index))
            }
            index += 1
        }
    }

    /// Numbers the next capture group, recording its `name` if it has one.
    /// - Returns: The group's index.
    /// - Throws: ``PatternError/limit(_:)`` when the pattern has more groups than ``Pattern/Limits/maxCaptureGroups``.
    mutating func claimCapture(named name: String?) throws(PatternError) -> Int {
        guard captureCount < limits.maxCaptureGroups else { throw .limit(.captureCount) }
        captureCount += 1
        if let name { names[name] = captureCount }
        return captureCount
    }
}
