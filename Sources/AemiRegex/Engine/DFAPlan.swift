/// What the DFA pipeline needs beyond the forward program: the reversed program and the byte classes of both.
struct DFAPlan: Sendable {
    let reverse: Program
    let forwardClasses: ByteClasses
    let reverseClasses: ByteClasses

    /// Whether the DFA can run `program`. It cannot when a loop of empty-width steps passes through an assertion.
    ///
    /// The DFA resolves an assertion only when the next byte is known, so the part of the closure after it is built later, with a fresh
    /// record of what was visited. The Pike VM builds the whole closure at once and never walks a loop twice. Without an assertion in
    /// the loop the two agree; with one, the DFA can go round once more and reorder the alternatives (a generated pattern found it:
    /// `(?i:\B*?\B|a)*`). Such patterns are rare and take the Pike VM, which is correct for them.
    /// - Complexity: O(instructions).
    static func isEligible(_ program: Program) -> Bool {
        !hasAssertionInEmptyLoop(program)
    }

    /// An iterative depth-first search over the empty-width edges (jump, split, save, assertion) for a cycle that contains an assertion.
    private static func hasAssertionInEmptyLoop(_ program: Program) -> Bool {
        let instructions = program.instructions
        guard instructions.contains(where: { $0.op == .assertion }) else { return false }
        func successors(_ pc: Int) -> [Int] {
            let instruction = instructions[pc]
            switch instruction.op {
                case .jump: return [pc + Int(instruction.x)]
                case .split: return [pc + Int(instruction.x), pc + Int(instruction.y)]
                case .save, .assertion: return [pc + 1]
                case .byteRange, .byteSet, .match: return []
            }
        }
        // 0 not visited, 1 on the current path, 2 finished.
        var state = [UInt8](repeating: 0, count: instructions.count)
        for start in 0 ..< instructions.count where state[start] == 0 {
            var path = [start]
            var pending = [successors(start)]
            state[start] = 1
            while let last = pending.indices.last {
                guard let next = pending[last].popLast() else {
                    state[path[last]] = 2
                    path.removeLast()
                    pending.removeLast()
                    continue
                }
                switch state[next] {
                    case 1:
                        let cycleStart = path.firstIndex(of: next) ?? 0
                        if path[cycleStart...].contains(where: { instructions[$0].op == .assertion }) { return true }
                    case 0:
                        state[next] = 1
                        path.append(next)
                        pending.append(successors(next))
                    default:
                        break
                }
            }
        }
        return false
    }
}
