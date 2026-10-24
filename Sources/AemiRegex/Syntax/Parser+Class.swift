extension Parser {
    /// Parses a bracketed class at the current position and emits it.
    mutating func parseClass() throws(PatternError) {
        let open = offset(position)
        position += 1
        var negated = false
        if peek() == 0x5E {
            negated = true
            position += 1
        }
        var ranges: [ClosedRange<UInt32>] = []
        var named = ScalarSet()
        var first = true
        while true {
            guard let c = peek() else { throw .syntax(.unterminatedClass, offset: open) }
            if c == 0x5D, !first {
                position += 1
                break
            }
            first = false
            if c == 0x5B, peek(1) == 0x3A, let set = try parsePosixClass() {
                named = named.union(set)
                continue
            }
            let itemOffset = offset(position)
            switch try parseClassItem() {
                case .set(let set):
                    named = named.union(set)
                case .scalar(let low):
                    ranges.append(low ... (try parseRangeEnd(after: low, itemOffset: itemOffset)))
            }
        }
        var set = ScalarSet(normalizing: ranges).union(named)
        if flags.ignoreCase { set = set.foldedASCII() }
        try emitSet(negated ? set.negated() : set)
    }

    private enum ClassItem {
        case scalar(UInt32)
        case set(ScalarSet)
    }

    private mutating func parseClassItem() throws(PatternError) -> ClassItem {
        guard let c = peek() else { throw .syntax(.unterminatedClass, offset: offset(scalars.count)) }
        guard c == 0x5C else {
            position += 1
            return .scalar(c)
        }
        switch try parseEscape(inClass: true) {
            case .scalar(let scalar): return .scalar(scalar)
            case .set(let set): return .set(set)
            case .assertion, .quote: throw .syntax(.invalidEscape, offset: offset(position))
        }
    }

    /// After a scalar `low`: `-high` makes a range; a `-` before `]` or the end is a literal and is left for the caller.
    private mutating func parseRangeEnd(after low: UInt32, itemOffset: Int) throws(PatternError) -> UInt32 {
        guard peek() == 0x2D, let after = peek(1), after != 0x5D else { return low }
        position += 1
        guard case .scalar(let high) = try parseClassItem(), high >= low else {
            throw .syntax(.invalidClassRange, offset: itemOffset)
        }
        return high
    }

    /// `[:name:]` or `[:^name:]` at the current position. Returns `nil`, consuming nothing, when no closing `:]` follows.
    private mutating func parsePosixClass() throws(PatternError) -> ScalarSet? {
        var end = position + 2
        while end + 1 < scalars.count, !(scalars[end] == 0x3A && scalars[end + 1] == 0x5D) { end += 1 }
        guard end + 1 < scalars.count else { return nil }
        var nameStart = position + 2
        var negated = false
        if scalars[nameStart] == 0x5E {
            negated = true
            nameStart += 1
        }
        var name = ""
        for scalar in scalars[nameStart ..< end] { name.unicodeScalars.append(Unicode.Scalar(scalar) ?? "?") }
        guard let set = ClassCatalog.posix(name) else { throw .syntax(.unknownClassName, offset: offset(position)) }
        position = end + 2
        return negated ? set.negated() : set
    }
}
