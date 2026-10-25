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

    /// Whether every match must end at the end of the text: every path from the start to `match` crosses a `\z` (or non-multiline `$`)
    /// assertion. Such a pattern is searched backwards from the end: the reverse DFA finds the leftmost start and reads only what the
    /// match covers, so a long haystack costs nothing beyond that.
    ///
    /// The rule is conservative: a path that avoids the assertion, or one the analysis cannot prove crosses it, answers `false`.
    /// It walks backwards from `match` over empty-width edges and stops at an end-of-text assertion; reaching an instruction that consumes
    /// a byte just before `match`, or the program's first instruction, means a match can end elsewhere.
    /// - Complexity: O(instructions).
    static func isEndAnchored(_ program: Program) -> Bool {
        let instructions = program.instructions
        guard let matchPC = instructions.indices.last(where: { instructions[$0].op == .match }),
            instructions.contains(where: { $0.op == .assertion && $0.x == Int32(Assertion.endText.rawValue) })
        else { return false }
        // predecessors[t]: the instructions with an edge to t, consuming edges included.
        var predecessors = [[Int]](repeating: [], count: instructions.count)
        for (pc, instruction) in instructions.enumerated() {
            switch instruction.op {
                case .jump: predecessors[pc + Int(instruction.x)].append(pc)
                case .split:
                    predecessors[pc + Int(instruction.x)].append(pc)
                    predecessors[pc + Int(instruction.y)].append(pc)
                case .save, .assertion, .byteRange, .byteSet: predecessors[pc + 1].append(pc)
                case .match: break
            }
        }
        var visited = [Bool](repeating: false, count: instructions.count)
        var stack = [matchPC]
        visited[matchPC] = true
        while let target = stack.popLast() {
            if target == 0 { return false }
            for predecessor in predecessors[target] {
                let instruction = instructions[predecessor]
                switch instruction.op {
                    case .assertion where instruction.x == Int32(Assertion.endText.rawValue):
                        continue  // this path crosses the end-of-text assertion; what lies before it does not matter
                    case .byteRange, .byteSet:
                        return false  // a byte is consumed and then the program matches: a match can end before the end
                    default:
                        if !visited[predecessor] {
                            visited[predecessor] = true
                            stack.append(predecessor)
                        }
                }
            }
        }
        return true
    }
}
