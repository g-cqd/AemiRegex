extension BTParser {
    /// Parses a brace quantifier at the current position, or returns `nil` when the text is not one.
    func parseBraces() throws(PatternError) -> (min: Int, max: Int?, length: Int)? {
        try braces(spaces: !isECMAScript, openMinimum: !isECMAScript)
    }

    /// Applies a quantifier to the last item of the branch. `length` is how many scalars the operator itself uses.
    mutating func quantify(min: Int, max: Int?, length: Int) throws(PatternError) {
        let at = offset(position)
        guard let operand = top.items.last else { throw .syntax(.repetitionWithoutOperand, offset: at) }
        guard !top.lastIsQuantified else { throw .syntax(.nestedRepetition, offset: at) }
        switch nodes[operand].kind {
            case .assertion, .keep: throw .syntax(.repetitionWithoutOperand, offset: at)
            default: break
        }
        if isECMAScript, isAssertionLike(operand) { throw .syntax(.repetitionWithoutOperand, offset: at) }
        position += length
        var mode = BTRepeatMode.greedy
        if peek() == 0x3F {
            mode = .lazy
            position += 1
        } else if peek() == 0x2B, !isECMAScript {
            mode = .possessive
            position += 1
        }
        let node = try newNode(.repetition(min: min, max: max, mode: mode), children: [operand])
        top.items[top.items.count - 1] = node
        top.lastIsQuantified = true
    }

    func isAssertionLike(_ index: Int) -> Bool {
        switch nodes[index].kind {
            case .assertion, .look: true
            default: false
        }
    }
}
