extension IRegexp {
    /// The one-pass validator and translator behind ``IRegexp/translate(_:limits:)``.
    struct Translator {
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
    }
}
