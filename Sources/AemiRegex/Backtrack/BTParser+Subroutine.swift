extension BTParser {
    /// Parses `(?R)`, `(?1)`, `(?+1)`, `(?-1)` and `(?&name)`: a call to a group as a subroutine. The position is at the opening parenthesis.
    mutating func parseCall(at: Int) throws(PatternError) {
        switch scalars[position + 2] {
            case 0x52:
                guard peek(3) == 0x29 else { throw .syntax(.invalidGroupSyntax, offset: at) }
                try add(.call(group: 0))
                position += 4
            case 0x26: try addNamedCall(from: position + 3, close: 0x29, at: at)
            default: try addNumberedCall(from: position + 2, close: 0x29, at: at)
        }
    }

    /// A call by number from `start`: `3`, `+1` (the next group to open) or `-1` (the last one opened), ending at `close`.
    mutating func addNumberedCall(from start: Int, close: UInt32, at: Int) throws(PatternError) {
        var index = start
        let sign = scalars[index] == 0x2B ? 1 : scalars[index] == 0x2D ? -1 : 0
        if sign != 0 { index += 1 }
        guard let number = number(at: &index), index < scalars.count, scalars[index] == close else {
            throw .syntax(.invalidGroupSyntax, offset: at)
        }
        let group = sign > 0 ? captureCount + number : sign < 0 ? captureCount + 1 - number : number
        guard group >= 0 else { throw .syntax(.invalidGroupSyntax, offset: at) }
        pendingGroups.append((group, at))
        try add(.call(group: group))
        position = index + 1
    }

    mutating func addNamedCall(from start: Int, close: UInt32, at: Int) throws(PatternError) {
        try addNamedUse(from: start, close: close, at: at) { .namedCall(name: $0) }
    }

    // MARK: Conditionals

    /// Opens `(?(condition)yes|no)`. The position is at the opening parenthesis.
    ///
    /// A look-around condition is left for the main loop: the group that follows `(?` is read as a look-around, and ``closeGroup()`` keeps
    /// it out of the branches.
    mutating func openConditional(open: Int) throws(PatternError) {
        let at = offset(position + 1)
        push(.conditional, open: open)
        if peek(3) == 0x3F {
            top.condition = .lookaround
            position += 2
            return
        }
        let start = position + 3
        guard let close = scalars[start...].firstIndex(of: 0x29), close > start else {
            throw .syntax(.invalidGroupSyntax, offset: at)
        }
        top.condition = try condition(text(start ..< close), at: at)
        position = close + 1
    }

    /// Reads the test of a conditional: a group number (absolute or relative), a name, `R`, `R1` or `DEFINE`.
    private mutating func condition(_ text: String, at: Int) throws(PatternError) -> BTCondition {
        let scalars = Array(text.unicodeScalars.map(\.value))
        if text == "DEFINE" { return .define }
        if text == "R" { return .recursion(nil) }
        if scalars.count > 1, scalars[0] == 0x52, scalars[1...].allSatisfy({ (0x30 ... 0x39).contains($0) }) {
            return .recursion(Int(text.dropFirst()))
        }
        if text.hasPrefix("R&") { throw .syntax(.unsupported, offset: at) }
        if let first = scalars.first, (0x30 ... 0x39).contains(first) || first == 0x2B || first == 0x2D {
            guard let number = Int(text.hasPrefix("+") ? String(text.dropFirst()) : text), !text.isEmpty else {
                throw .syntax(.invalidGroupSyntax, offset: at)
            }
            let group = first == 0x2B ? captureCount + number : first == 0x2D ? captureCount + 1 + number : number
            guard group >= 1 else { throw .syntax(.invalidGroupSyntax, offset: at) }
            pendingGroups.append((group, at))
            return .group(group)
        }
        let bare = scalars.first == 0x3C || scalars.first == 0x27 ? Array(scalars.dropFirst().dropLast()) : scalars
        guard let first = bare.first, bare.enumerated().allSatisfy({ isNameScalar($1, first: $0 == 0) }), first != 0
        else {
            throw .syntax(.invalidGroupName, offset: at)
        }
        let name = String(String.UnicodeScalarView(bare.compactMap(Unicode.Scalar.init)))
        pendingNames.append((name, at))
        return .namedGroup(name)
    }

    /// The node for a conditional that has just closed: its test if it is a look-around, then `yes`, then `no` (empty when absent).
    mutating func conditionalNode(of frame: BTFrame) throws(PatternError) -> Int {
        guard let condition = frame.condition else { throw .syntax(.invalidGroupSyntax, offset: frame.openOffset) }
        let branches = frame.branches + [try concatenation(of: frame.items)]
        guard branches.count <= (condition == .define ? 1 : 2) else {
            throw .syntax(.invalidGroupSyntax, offset: frame.openOffset)
        }
        var children = [branches[0], branches.count == 2 ? branches[1] : try newNode(.empty)]
        if condition == .lookaround {
            guard let look = frame.conditionNode else { throw .syntax(.invalidGroupSyntax, offset: frame.openOffset) }
            children.insert(look, at: 0)
        }
        return try newNode(.conditional(condition), children: children)
    }
}
