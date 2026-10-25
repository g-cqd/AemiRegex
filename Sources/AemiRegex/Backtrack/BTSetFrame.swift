/// One class being read in `v` mode: the operands so far, and how they combine. Nested classes stack up, so no depth overflows the call stack.
struct BTSetFrame {
    enum Combination {
        case none, union, intersection, subtraction

        var isOperator: Bool { self == .intersection || self == .subtraction }
    }

    var negated: Bool
    var openOffset: Int
    var value: BTStringSet?
    var combination = Combination.none
    var operandCount = 0
    /// Whether the last thing read was `--` or `&&`, which needs an operand after it.
    var pendingOperator = false
    /// Whether the last operand was a range, which `--` and `&&` cannot take as an operand.
    var lastWasRange = false

    /// Adds an operand with the combination chosen so far; the first operand starts the value.
    /// - Returns: `false` when the operand is not allowed here: after `--` or `&&` chains, a bare operand needs an operator before it.
    mutating func feed(_ operand: BTStringSet) -> Bool {
        if operandCount >= 1, !pendingOperator {
            guard combination == .none || combination == .union else { return false }
            combination = .union
        }
        pendingOperator = false
        operandCount += 1
        guard let current = value else {
            value = operand
            return true
        }
        switch combination {
            case .none, .union: value = current.union(operand)
            case .intersection: value = current.intersection(operand)
            case .subtraction: value = current.subtracting(operand)
        }
        return true
    }
}
