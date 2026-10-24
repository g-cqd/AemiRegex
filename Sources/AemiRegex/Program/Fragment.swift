/// Builders for instruction fragments. A fragment is position independent: its jumps are relative.
enum Fragment {
    /// `first | second | …`: each branch is tried in order, and the first that leads to a match wins.
    static func alternation(_ branches: [[Instruction]]) -> [Instruction] {
        guard branches.count > 1 else { return branches.first ?? [] }
        let total = branches.reduce(0) { $0 + $1.count } + 2 * (branches.count - 1)
        var code: [Instruction] = []
        code.reserveCapacity(total)
        for (index, branch) in branches.enumerated() {
            if index == branches.count - 1 {
                code += branch
            } else {
                code.append(.split(1, branch.count + 2))
                code += branch
                code.append(.jump(total - code.count))
            }
        }
        return code
    }

    /// The code for `atom{min,max}`. `max == nil` means no upper bound. `nullable` says the atom can match the empty string.
    static func repetition(
        of atom: [Instruction], min: Int, max: Int?, greedy: Bool, nullable: Bool
    ) -> [Instruction] {
        let length = atom.count
        func choose(_ enter: Int, _ skip: Int) -> Instruction { greedy ? .split(enter, skip) : .split(skip, enter) }
        var code: [Instruction] = []
        switch (min, max) {
            case (0, 0?): return []
            case (0, nil):
                if nullable {
                    // `(x+)?` instead of `(x*)`: a loop whose body can match empty would otherwise lose its captures.
                    code.append(choose(1, length + 2))
                    code += atom
                    code.append(choose(-length, 1))
                } else {
                    code.append(choose(1, length + 2))
                    code += atom
                    code.append(.jump(-(length + 1)))
                }
            case (_, nil):
                for _ in 1 ..< min { code += atom }
                code += atom
                code.append(choose(-length, 1))
            case (_, let upper?):
                for _ in 0 ..< min { code += atom }
                var optional: [Instruction] = []
                for _ in 0 ..< (upper - min) {
                    optional = [choose(1, length + 1 + optional.count)] + atom + optional
                }
                code += optional
        }
        return code
    }
}
