extension BTCompiler {
    /// `body{min,max}` as the required copies, then either a loop (no upper bound) or nested optional copies.
    mutating func repetition(
        _ body: BTFragment, min: Int, max: Int?, mode: BTRepeatMode
    ) throws(PatternError) -> BTFragment {
        let copies = Swift.max(max ?? (min + 1), 1)
        guard body.code.count * copies + 4 * copies <= limits.maxProgramSize else { throw .limit(.programSize) }
        let isECMAScript = dialect == .ecmaScript
        var iteration = body.code
        if isECMAScript, let groups = body.groups {
            // ECMAScript clears the captures inside a group at the start of each repetition.
            iteration.insert(BTInstruction(.resetCaptures, groups.lowerBound, groups.upperBound), at: 0)
        }
        let register = body.canBeEmpty && max != 0 ? newRegister() : nil
        func choose(_ enter: Int, _ skip: Int) -> BTInstruction {
            BTInstruction(.split, mode == .lazy ? skip : enter, mode == .lazy ? enter : skip)
        }
        func guarded(exit: Int) -> [BTInstruction] {
            guard let register else { return iteration }
            return [BTInstruction(.setRegister, register)] + iteration
                + [BTInstruction(.emptyCheck, register, isECMAScript ? 0 : exit)]
        }

        var code: [BTInstruction] = []
        for _ in 0 ..< min { code += iteration }
        if let max {
            var tail: [BTInstruction] = []
            for _ in 0 ..< max - min {
                let inner = guarded(exit: 1 + tail.count)
                tail = [choose(1, inner.count + 1 + tail.count)] + inner + tail
            }
            code += tail
        } else {
            let inner = guarded(exit: 2)
            code.append(choose(1, inner.count + 2))
            code += inner
            code.append(BTInstruction(.jump, -(inner.count + 1)))
        }
        if mode == .possessive {
            code = [BTInstruction(.atomicStart)] + code + [BTInstruction(.atomicEnd)]
        }
        let longest: Int? = body.maxLength == 0 ? 0 : max.flatMap { count in body.maxLength.map { count * $0 } }
        return BTFragment(
            code: code, canBeEmpty: min == 0 || body.canBeEmpty, groups: body.groups, minLength: min * body.minLength,
            maxLength: longest)
    }

    private mutating func newRegister() -> Int {
        registerCount += 1
        return 2 * (tree.captureCount + 1) + registerCount - 1
    }
}
