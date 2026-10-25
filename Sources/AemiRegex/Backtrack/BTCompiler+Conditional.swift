extension BTCompiler {
    /// Points each `call` at the code of its group: the first copy of the group's opening `save`, or the start of the program for group 0.
    static func patchCalls(in code: inout [BTInstruction]) throws(PatternError) {
        var opening: [Int: Int] = [0: 0]
        for (pc, instruction) in code.enumerated()
        where instruction.op == .save && instruction.y == 0 && instruction.x % 2 == 0 {
            let group = Int(instruction.x) / 2
            if opening[group] == nil { opening[group] = pc }
        }
        for pc in code.indices where code[pc].op == .call {
            guard let target = opening[Int(code[pc].y)] else { throw .syntax(.invalidGroupSyntax, offset: 0) }
            code[pc].x = Int32(truncatingIfNeeded: target - pc)
        }
    }

    /// `(?(condition)yes|no)`. `children` are the look-around of a look-around condition if any, then `yes`, then `no`.
    func conditional(_ condition: BTCondition, _ children: [BTFragment]) throws(PatternError) -> BTFragment {
        let (yes, no) = (children[children.count - 2], children[children.count - 1])
        var merged = BTFragment.joining([yes, no], backward: false)
        merged.canBeEmpty = yes.canBeEmpty || no.canBeEmpty
        merged.minLength = min(yes.minLength, no.minLength)
        merged.maxLength = yes.maxLength.flatMap { y in no.maxLength.map { max(y, $0) } }
        switch condition {
            case .define:
                merged.code = [BTInstruction(.jump, yes.code.count + 1)] + yes.code
                merged.canBeEmpty = true
                merged.minLength = 0
                merged.maxLength = 0
            case .lookaround:
                merged.code = lookaroundCondition(children[0].code, yes: yes.code, no: no.code)
                merged.groups = BTFragment.merged(merged.groups, children[0].groups)
            case .group(let group):
                merged.code = test(BTInstruction(.condGroup, group), yes: yes.code, no: no.code)
            case .namedGroup(let name):
                guard let group = tree.names[name]?.first else { throw .syntax(.invalidGroupName, offset: 0) }
                merged.code = test(BTInstruction(.condGroup, group), yes: yes.code, no: no.code)
            case .recursion(let group):
                merged.code = test(BTInstruction(.condRecursion, group ?? -1), yes: yes.code, no: no.code)
        }
        return merged
    }

    /// `test`, then `yes`, then a jump over `no`, then `no`; `test` skips to `no` when it fails.
    private func test(_ test: BTInstruction, yes: [BTInstruction], no: [BTInstruction]) -> [BTInstruction] {
        var head = test
        head.y = Int32(yes.count + 2)
        return [head] + yes + [BTInstruction(.jump, no.count + 1)] + no
    }

    /// A look-around as the test: its own start and end are rewritten so that its failing or succeeding picks a branch instead of failing.
    private func lookaroundCondition(_ look: [BTInstruction], yes: [BTInstruction], no: [BTInstruction])
        -> [BTInstruction]
    {
        var code = look
        let negative = look[0].x == 1
        let end = code.count - 1
        code[0].x = negative ? 5 : 4
        code[end].x = negative ? 5 : 4
        if negative {
            code[0].y = Int32(code.count)  // the body failing: the assertion holds, so `yes`
            code[end].y = Int32(yes.count + 2)  // the body matching: it does not, so `no`
        } else {
            code[0].y = Int32(code.count + yes.count + 1)  // the body failing: `no`
        }
        return code + yes + [BTInstruction(.jump, no.count + 1)] + no
    }
}
