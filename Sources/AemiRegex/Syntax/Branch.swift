/// The instructions of one alternative of a group, with where each atom starts, so the concatenation can be emitted in either order.
struct Branch {
    var code: [Instruction] = []
    private(set) var atomStarts: [Int] = []

    mutating func append(_ atom: [Instruction]) {
        atomStarts.append(code.count)
        code += atom
    }

    /// The code, with atoms in reverse order when `reversed`. Each atom's own code is already reversed by the parser.
    ///
    /// - Complexity: O(code size).
    func ordered(reversed: Bool) -> [Instruction] {
        guard reversed else { return code }
        var result: [Instruction] = []
        result.reserveCapacity(code.count)
        var end = code.count
        for start in atomStarts.reversed() {
            result += code[start ..< end]
            end = start
        }
        return result
    }
}
