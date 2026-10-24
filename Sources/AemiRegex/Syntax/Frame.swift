/// One open group while parsing: the root, or a parenthesised group. Instructions are built here, so no syntax tree exists.
struct Frame {
    enum Kind: Equatable {
        case root
        /// A group; `capture` is its index, or `nil` for `(?:…)` and `(?flags:…)`.
        case group(capture: Int?)
    }

    /// The most recent atom of the current branch: what a following quantifier applies to.
    struct Operand {
        var start: Int
        var nullable: Bool
        /// Whether the branch before this atom can match empty.
        var nullableBefore: Bool
    }

    var kind: Kind
    /// Byte offset of the opening parenthesis, for error reports.
    var openOffset: Int
    /// The flags to restore when the group closes.
    var savedFlags: Flags
    var branches: [Branch] = []
    var branchesNullable = false
    var current = Branch()
    var currentNullable = true
    var last: Operand?
    var lastWasRepetition = false

    mutating func push(_ atom: [Instruction], nullable: Bool) {
        last = Operand(start: current.code.count, nullable: nullable, nullableBefore: currentNullable)
        current.append(atom)
        currentNullable = currentNullable && nullable
        lastWasRepetition = false
    }

    mutating func startNextBranch() {
        branches.append(current)
        branchesNullable = branchesNullable || currentNullable
        current = Branch()
        currentNullable = true
        last = nil
        lastWasRepetition = false
    }

    /// The code of the whole group, and whether it can match empty. With `reversed`, each branch's atoms come in reverse order.
    func finished(reversed: Bool) -> (code: [Instruction], nullable: Bool) {
        guard !branches.isEmpty else { return (current.ordered(reversed: reversed), currentNullable) }
        let all = (branches + [current]).map { $0.ordered(reversed: reversed) }
        return (Fragment.alternation(all), branchesNullable || currentNullable)
    }
}
