extension Parser {
    /// Parses `{n}`, `{n,}` or `{n,m}` at the current position. Returns `nil` when the text is not a repetition, so `{` is a literal.
    func parseBraces() throws(PatternError) -> (min: Int, max: Int?, length: Int)? {
        var index = position + 1
        guard let minimum = number(at: &index) else { return nil }
        var maximum: Int? = minimum
        if index < scalars.count, scalars[index] == 0x2C {
            index += 1
            maximum = number(at: &index)
        }
        guard index < scalars.count, scalars[index] == 0x7D else { return nil }
        if let maximum, maximum < minimum { throw .syntax(.invalidRepetition, offset: offset(position)) }
        guard minimum <= limits.maxRepetition, (maximum ?? 0) <= limits.maxRepetition else {
            throw .limit(.repetitionCount)
        }
        return (minimum, maximum, index + 1 - position)
    }

    /// Reads decimal digits, saturating so that a long run of digits cannot overflow.
    private func number(at index: inout Int) -> Int? {
        var value: Int?
        while index < scalars.count, (0x30 ... 0x39).contains(scalars[index]) {
            value = Swift.min((value ?? 0) * 10 + Int(scalars[index] - 0x30), 1_000_000)
            index += 1
        }
        return value
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

        let atom = Array(top.current[operand.start...])
        let copies = Swift.max(max ?? (min + 1), 1)
        if emitted - atom.count + atom.count * copies + 2 * copies + 2 > limits.maxProgramSize {
            throw .limit(.programSize)
        }
        let code = Fragment.repetition(of: atom, min: min, max: max, greedy: greedy, nullable: operand.nullable)
        top.current.removeSubrange(operand.start...)
        top.current += code
        emitted += code.count - atom.count
        top.currentNullable = operand.nullableBefore && (min == 0 || operand.nullable)
        top.last = nil
        top.lastWasRepetition = true
    }
}
