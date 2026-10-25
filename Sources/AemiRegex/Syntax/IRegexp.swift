/// I-Regexp (RFC 9485): a strict check of the RFC's grammar and its translation to RE2 syntax, in one pass without recursion.
///
/// The translation is the RFC's own (section 5.4) with one correction: `.` outside a class becomes `[^\n\r]`, and `^` and `$` are
/// escaped. The RFC's text does not escape them, but its grammar makes them ordinary characters (as XSD does) and RE2 would read them as
/// anchors. Groups become non-capturing: I-Regexp has no captures. Whole-string matching is applied by the caller, at the program level.
///
/// Everything the grammar and the semantics allow us to check is checked here, with offsets in the text the caller wrote: a reversed
/// range, a repeat count out of order or over the limit, a category name outside the RFC's list. What the RE2 parser sees afterwards can
/// only fail on a limit (program size).
enum IRegexp {
    /// The RE2 source for `pattern`.
    /// - Throws: ``PatternError/syntax(_:offset:)`` with a byte offset in `pattern`, or a limit.
    /// - Complexity: O(pattern length); stack use is bounded by the nesting limit.
    static func translate(_ pattern: String, limits: Pattern.Limits) throws(PatternError) -> String {
        guard pattern.utf8.count <= limits.maxPatternBytes else { throw .limit(.patternLength) }
        var translator = Translator(pattern, limits: limits)
        try translator.run()
        return translator.output
    }

    private struct Translator {
        let scalars: [UInt32]
        let offsets: [Int]
        let limits: Pattern.Limits
        var output = ""
        /// Byte offsets of the `(` that are still open.
        var opens: [Int] = []

        init(_ pattern: String, limits: Pattern.Limits) {
            let text = PatternText(pattern)
            scalars = text.scalars
            offsets = text.offsets
            self.limits = limits
            output.reserveCapacity(pattern.utf8.count * 2)
        }

        func offset(_ index: Int) -> Int { offsets[min(index, offsets.count - 1)] }

        mutating func run() throws(PatternError) {
            var index = 0
            var canQuantify = false
            var afterQuantifier = false
            while index < scalars.count {
                let c = scalars[index]
                switch c {
                    case 0x7C:  // |
                        output += "|"
                        canQuantify = false
                        afterQuantifier = false
                        index += 1
                    case 0x28:  // (
                        guard opens.count < limits.maxNestingDepth else { throw .limit(.nestingDepth) }
                        opens.append(offset(index))
                        output += "(?:"
                        canQuantify = false
                        afterQuantifier = false
                        index += 1
                    case 0x29:  // )
                        guard opens.popLast() != nil else { throw .syntax(.unmatchedCloseParen, offset: offset(index)) }
                        output += ")"
                        canQuantify = true
                        afterQuantifier = false
                        index += 1
                    case 0x2A, 0x2B, 0x3F:  // * + ?
                        guard canQuantify else {
                            throw .syntax(
                                afterQuantifier ? .nestedRepetition : .repetitionWithoutOperand, offset: offset(index))
                        }
                        output.unicodeScalars.append(Unicode.Scalar(c) ?? "?")
                        canQuantify = false
                        afterQuantifier = true
                        index += 1
                    case 0x7B:  // {
                        guard canQuantify else {
                            throw .syntax(
                                afterQuantifier ? .nestedRepetition : .repetitionWithoutOperand, offset: offset(index))
                        }
                        index = try range(at: index)
                        canQuantify = false
                        afterQuantifier = true
                    case 0x2E:  // .
                        output += "[^\\n\\r]"
                        canQuantify = true
                        afterQuantifier = false
                        index += 1
                    case 0x5B:  // [
                        index = try characterClass(at: index)
                        canQuantify = true
                        afterQuantifier = false
                    case 0x5C:  // \
                        index = try escape(at: index, inClass: false)
                        canQuantify = true
                        afterQuantifier = false
                    default:
                        guard Self.isNormalChar(c) else { throw .syntax(.invalidCharacter, offset: offset(index)) }
                        appendLiteral(c, inClass: false)
                        canQuantify = true
                        afterQuantifier = false
                        index += 1
                }
            }
            if let innermost = opens.last { throw .syntax(.unmatchedOpenParen, offset: innermost) }
        }

        // MARK: Pieces

        /// NormalChar of the ABNF: everything except `( ) * + . ? [ \ ] { | }` and the surrogates.
        static func isNormalChar(_ c: UInt32) -> Bool {
            c <= 0x27 || c == 0x2C || c == 0x2D || (0x2F ... 0x3E).contains(c) || (0x40 ... 0x5A).contains(c)
                || (0x5E ... 0x7A).contains(c) || (0x7E ... 0xD7FF).contains(c) || (0xE000 ... 0x10FFFF).contains(c)
        }

        /// CCchar of the ABNF (without the escape form): not `-`, `[`, `\` or `]`.
        static func isClassChar(_ c: UInt32) -> Bool {
            c <= 0x2C || (0x2E ... 0x5A).contains(c) || (0x5E ... 0xD7FF).contains(c)
                || (0xE000 ... 0x10FFFF).contains(c)
        }

        /// The scalar a SingleCharEsc stands for, given the character after the backslash, or `nil` when it is none.
        static func singleEscape(_ e: UInt32) -> UInt32? {
            switch e {
                case 0x6E: 0x0A
                case 0x72: 0x0D
                case 0x74: 0x09
                case 0x28 ... 0x2B, 0x2D, 0x2E, 0x3F, 0x5B ... 0x5E, 0x7B ... 0x7D: e
                default: nil
            }
        }

        /// Appends `c` so that RE2 reads it as that character: control characters in hex, ASCII punctuation escaped, the rest as is.
        mutating func appendLiteral(_ c: UInt32, inClass: Bool) {
            if c < 0x20 || c == 0x7F {
                output += "\\x{" + String(c, radix: 16) + "}"
            } else if c < 0x80, !Self.isAlphanumeric(c), c != 0x20 {
                output += "\\"
                output.unicodeScalars.append(Unicode.Scalar(c) ?? "?")
            } else {
                output.unicodeScalars.append(Unicode.Scalar(c) ?? "?")
            }
        }

        static func isAlphanumeric(_ c: UInt32) -> Bool {
            (0x30 ... 0x39).contains(c) || (0x41 ... 0x5A).contains(c) || (0x61 ... 0x7A).contains(c)
        }

        /// `{n}`, `{n,}` or `{n,m}` at `index`. Returns the index after it.
        mutating func range(at index: Int) throws(PatternError) -> Int {
            func digits(_ from: Int) -> (value: Int, end: Int)? {
                var value = 0
                var end = from
                while end < scalars.count, (0x30 ... 0x39).contains(scalars[end]) {
                    value = min(value * 10 + Int(scalars[end] - 0x30), 1_000_000)
                    end += 1
                }
                return end == from ? nil : (value, end)
            }
            let open = offset(index)
            guard let low = digits(index + 1) else { throw .syntax(.invalidRepetition, offset: open) }
            var end = low.end
            var high: Int? = low.value
            var hasComma = false
            if end < scalars.count, scalars[end] == 0x2C {
                hasComma = true
                end += 1
                high = digits(end).map { $0.value }
                if let parsed = digits(end) { end = parsed.end }
            }
            guard end < scalars.count, scalars[end] == 0x7D else { throw .syntax(.invalidRepetition, offset: open) }
            if let high, high < low.value { throw .syntax(.invalidRepetition, offset: open) }
            guard low.value <= limits.maxRepetition, (high ?? 0) <= limits.maxRepetition else {
                throw .limit(.repetitionCount)
            }
            output += "{\(low.value)"
            if hasComma { output += "," + (high.map(String.init) ?? "") }
            output += "}"
            return end + 1
        }

        /// A `\` escape at `index`, in or out of a class. Returns the index after it.
        mutating func escape(at index: Int, inClass: Bool) throws(PatternError) -> Int {
            let start = offset(index)
            guard index + 1 < scalars.count else { throw .syntax(.unexpectedEnd, offset: start) }
            let e = scalars[index + 1]
            if let literal = Self.singleEscape(e) {
                appendLiteral(literal, inClass: inClass)
                return index + 2
            }
            guard e == 0x70 || e == 0x50 else { throw .syntax(.invalidEscape, offset: start) }
            guard index + 2 < scalars.count, scalars[index + 2] == 0x7B else {
                throw .syntax(.invalidEscape, offset: start)
            }
            var end = index + 3
            var name = ""
            while end < scalars.count, scalars[end] != 0x7D, name.unicodeScalars.count < 4 {
                name.unicodeScalars.append(Unicode.Scalar(scalars[end]) ?? "?")
                end += 1
            }
            guard end < scalars.count, scalars[end] == 0x7D, UnicodeProperties.isGeneralCategory(name) else {
                throw .syntax(.unknownClassName, offset: start)
            }
            output += (e == 0x70 ? "\\p{" : "\\P{") + name + "}"
            return end + 1
        }

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
}
