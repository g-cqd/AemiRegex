extension BTParser {
    /// Parses an escape outside a class: an assertion, a back reference, a character, or a set.
    mutating func parseAtomEscape() throws(PatternError) {
        let at = offset(position)
        guard let c = peek(1) else { throw .syntax(.unexpectedEnd, offset: offset(scalars.count)) }
        switch c {
            case 0x62, 0x42:
                let folded = isECMAScript && flags.ignoreCase
                switch (c == 0x62, folded) {
                    case (true, false): try add(.assertion(.wordBoundary))
                    case (false, false): try add(.assertion(.notWordBoundary))
                    case (true, true): try add(.assertion(.wordBoundaryFolded))
                    case (false, true): try add(.assertion(.notWordBoundaryFolded))
                }
                position += 2
            case 0x41 where !isECMAScript:
                try add(.assertion(.beginText))
                position += 2
            case 0x7A where !isECMAScript:
                try add(.assertion(.endText))
                position += 2
            case 0x5A where !isECMAScript:
                try add(.assertion(.endTextBeforeFinalNewline))
                position += 2
            case 0x6B: try namedReference(at: at)
            case 0x67 where !isECMAScript: try generalReference(at: at)
            case 0x31 ... 0x39: try decimalEscape(at: at)
            case 0x52 where !isECMAScript: try newlineSequence()
            case 0x4E where !isECMAScript:
                if peek(2) == 0x7B, peek(3) == 0x55, peek(4) == 0x2B {
                    // `\N{U+hhhh}` is a character; `\N{2}` is `\N` repeated twice.
                    position += 5
                    try addLiteral(try braced(radix: 16, allowSurrogates: true, at: at))
                } else {
                    try addSet(BTSets.lineTerminators(dialect).negated())
                    position += 2
                }
            case 0x51 where !isECMAScript: try quoted()
            case 0x45 where !isECMAScript: position += 2
            case 0x4B where !isECMAScript:
                // PCRE2 refuses `\K` inside a look-around, where the match start would move outside the match.
                if frames.contains(where: { if case .look = $0.kind { true } else { false } }) {
                    throw .syntax(.invalidEscape, offset: at)
                }
                try add(.keep)
                position += 2
            case 0x47 where !isECMAScript, 0x58 where !isECMAScript, 0x43 where !isECMAScript:
                throw .syntax(.unsupported, offset: at)
            default:
                switch try parseCharacterEscape(inClass: false) {
                    case .scalar(let scalar): try addLiteral(scalar)
                    case .set(let set), .fixedSet(let set): try addSet(set)
                }
        }
    }

    /// Adds a back reference to the group called by the name that starts at `start` and ends at `close`.
    mutating func addNamedReference(from start: Int, close: UInt32, at: Int) throws(PatternError) {
        let ignoreCase = flags.ignoreCase
        try addNamedUse(from: start, close: close, at: at) { .namedBackReference(name: $0, ignoreCase: ignoreCase) }
    }

    /// Reads a group name from `start` to `close`, records that the pattern must have such a group, and adds the node `make` builds for it.
    mutating func addNamedUse(
        from start: Int, close: UInt32, at: Int, _ make: (String) -> BTNode.Kind
    ) throws(PatternError) {
        let parsed = try name(from: start, until: close) { isNameScalar($0, first: $1) }
        pendingNames.append((parsed.name, at))
        try add(make(parsed.name))
        position = parsed.end + 1
    }

    private mutating func reference(group: Int, at: Int) throws(PatternError) {
        pendingGroups.append((group, at))
        try add(.backReference(group: group, ignoreCase: flags.ignoreCase))
    }

    private mutating func decimalEscape(at: Int) throws(PatternError) {
        let start = position + 1
        var end = start
        var value = 0
        while end < scalars.count, (0x30 ... 0x39).contains(scalars[end]) {
            value = Swift.min(value * 10 + Int(scalars[end] - 0x30), 1_000_000)
            end += 1
        }
        if isECMAScript || end - start == 1 || value <= totalGroups {
            position = end
            try reference(group: value, at: at)
            return
        }
        // PCRE2: a number that is not a group is an octal escape when it starts with an octal digit.
        guard scalars[start] <= 0x37 else { throw .syntax(.invalidEscape, offset: at) }
        position = start
        var scalar: UInt32 = 0
        var digits = 0
        while digits < 3, let digit = peek(), (0x30 ... 0x37).contains(digit) {
            scalar = scalar * 8 + (digit - 0x30)
            position += 1
            digits += 1
        }
        try addLiteral(scalar)
    }

    /// `\k<name>` (and in PCRE2 `\k'name'` and `\k{name}`).
    private mutating func namedReference(at: Int) throws(PatternError) {
        guard let open = peek(2) else { throw .syntax(.unexpectedEnd, offset: offset(scalars.count)) }
        let close: UInt32
        switch open {
            case 0x3C: close = 0x3E
            case 0x27 where !isECMAScript: close = 0x27
            case 0x7B where !isECMAScript: close = 0x7D
            default: throw .syntax(.invalidEscape, offset: at)
        }
        try addNamedReference(from: position + 3, close: close, at: at)
    }

    /// PCRE2's `\gN`, `\g{N}`, `\g{-N}` (relative) and `\g{name}`.
    private mutating func generalReference(at: Int) throws(PatternError) {
        guard let next = peek(2) else { throw .syntax(.unexpectedEnd, offset: offset(scalars.count)) }
        if next == 0x7B, let end = scalars[position...].firstIndex(of: 0x7D) {
            let body = scalars[(position + 3) ..< end]
            let text = String(String.UnicodeScalarView(body.compactMap(Unicode.Scalar.init)))
            if let number = Int(text) {
                let group = number < 0 ? captureCount + 1 + number : number
                guard group >= 1 else { throw .syntax(.invalidEscape, offset: at) }
                position = end + 1
                try reference(group: group, at: at)
            } else {
                try addNamedReference(from: position + 3, close: 0x7D, at: at)
            }
            return
        }
        if next == 0x3C || next == 0x27 {
            let close: UInt32 = next == 0x3C ? 0x3E : 0x27
            let first = peek(3) ?? 0
            if (0x30 ... 0x39).contains(first) || first == 0x2B || first == 0x2D {
                try addNumberedCall(from: position + 3, close: close, at: at)
            } else {
                try addNamedCall(from: position + 3, close: close, at: at)
            }
            return
        }
        guard (0x30 ... 0x39).contains(next) || next == 0x2D else { throw .syntax(.unsupported, offset: at) }
        var end = position + 2
        if scalars[end] == 0x2D { end += 1 }
        while end < scalars.count, (0x30 ... 0x39).contains(scalars[end]) { end += 1 }
        let text = String(String.UnicodeScalarView(scalars[(position + 2) ..< end].compactMap(Unicode.Scalar.init)))
        guard let number = Int(text) else { throw .syntax(.invalidEscape, offset: at) }
        let group = number < 0 ? captureCount + 1 + number : number
        guard group >= 1 else { throw .syntax(.invalidEscape, offset: at) }
        position = end
        try reference(group: group, at: at)
    }

    /// `\R`: `\r\n`, or one vertical space character, never giving back the `\n` of a `\r\n`.
    private mutating func newlineSequence() throws(PatternError) {
        sets.append(CharSet(ScalarSet(0x0D)))
        let carriage = try newNode(.set(sets.count - 1))
        sets.append(CharSet(ScalarSet(0x0A)))
        let feed = try newNode(.set(sets.count - 1))
        let pair = try newNode(.concatenation, children: [carriage, feed])
        sets.append(CharSet(BTSets.verticalSpace))
        let single = try newNode(.set(sets.count - 1))
        let either = try newNode(.alternation, children: [pair, single])
        try add(.atomic, children: [either])
        position += 2
    }

    /// `\Q…\E`: every scalar up to `\E` is a literal.
    private mutating func quoted() throws(PatternError) {
        position += 2
        while position < scalars.count {
            if scalars[position] == 0x5C, peek(1) == 0x45 {
                position += 2
                return
            }
            try addLiteral(scalars[position])
            position += 1
        }
    }
}
