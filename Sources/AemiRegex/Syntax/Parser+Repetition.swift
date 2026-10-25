extension Parser {
    /// Parses `{n}`, `{n,}` or `{n,m}` at the current position. Returns `nil` when the text is not a repetition, so `{` is a literal.
    func parseBraces() throws(PatternError) -> (min: Int, max: Int?, length: Int)? {
        try braces(spaces: false, openMinimum: false)
    }

    /// Applies a quantifier to the most recent atom. `length` is how many scalars the operator itself uses.
    mutating func repeatOperator(min: Int, max: Int?, length: Int) throws(PatternError) {
        let operatorOffset = offset(position)
        guard let operand = top.last else {
            throw .syntax(top.lastWasRepetition ? .nestedRepetition : .repetitionWithoutOperand, offset: operatorOffset)
        }
        position += length
        var greedy = true
        if peek() == 0x3F {
            greedy = false
            position += 1
        }
        if flags.swapGreed { greedy.toggle() }

        let atom = Array(top.current.code[operand.start...])
        let copies = Swift.max(max ?? (min + 1), 1)
        if emitted - atom.count + atom.count * copies + 2 * copies + 2 > limits.maxProgramSize {
            throw .limit(.programSize)
        }
        let code = Fragment.repetition(of: atom, min: min, max: max, greedy: greedy, nullable: operand.nullable)
        top.current.code.removeSubrange(operand.start...)
        top.current.code += code
        emitted += code.count - atom.count
        top.currentNullable = operand.nullableBefore && (min == 0 || operand.nullable)
        top.last = nil
        top.lastWasRepetition = true
    }
}
