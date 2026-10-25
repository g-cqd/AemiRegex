extension Program {
    /// For each instruction index, and one past the last, the instructions with an edge to it.
    ///
    /// The empty-width edges (`jump`, `split`, `save`, `assertion`) always count. With `consuming`, the edge from a byte-consuming
    /// instruction to the one after it counts too.
    /// - Complexity: O(instructions).
    func predecessors(includingConsuming consuming: Bool) -> [[Int]] {
        var result = [[Int]](repeating: [], count: instructions.count + 1)
        for (pc, instruction) in instructions.enumerated() {
            switch instruction.op {
                case .jump: result[pc + Int(instruction.x)].append(pc)
                case .split:
                    result[pc + Int(instruction.x)].append(pc)
                    result[pc + Int(instruction.y)].append(pc)
                case .save, .assertion: result[pc + 1].append(pc)
                case .byteRange, .byteSet: if consuming { result[pc + 1].append(pc) }
                case .match: break
            }
        }
        return result
    }
}
