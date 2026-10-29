internal import AemiKernel

/// Walks the instructions reachable from a program counter without consuming input, in priority order. The DFA uses it to build and
/// resolve states, and the literal analysis uses it to find what a match can start with.
struct EpsilonWalker {
    /// What to do at an assertion.
    enum Policy {
        /// Treat it as true: a superset of what any real position reaches.
        case pass
        /// Report it as an entry: the next byte is not known yet.
        case keep
        /// Follow it only if it holds between these neighbours.
        case check(previous: Int, next: Int)
    }

    private var visited: SparseSet
    private var stack: [Int] = []

    init(instructionCount: Int) { visited = SparseSet(capacity: instructionCount) }

    /// Forgets which instructions were visited. Call before a walk that must not share state with the previous one.
    mutating func reset() { visited.removeAll() }

    /// Appends the byte-consuming instructions, the `match`, and (under ``Policy/keep``) the assertions reachable from `start`.
    /// An instruction visited by an earlier walk since the last ``reset()`` is skipped.
    /// - Parameters:
    ///   - start: The program counter to walk from.
    ///   - instructions: The program.
    ///   - policy: What to do at an assertion.
    ///   - cutAtMatch: Stop at the first `match`: every thread after it has lower priority and can never win.
    ///   - list: Receives the program counters, in priority order.
    /// - Returns: Whether this walk added a `match`.
    mutating func walk(
        from start: Int, in instructions: ContiguousArray<Instruction>, policy: Policy, cutAtMatch: Bool,
        into list: inout [Int32]
    ) -> Bool {
        var matched = false
        stack.append(start)
        while let pc = stack.popLast() {
            if visited.contains(pc) { continue }
            visited.insert(pc)
            let instruction = instructions[pc]
            switch instruction.op {
                case .jump: stack.append(pc + Int(instruction.x))
                case .split:
                    stack.append(pc + Int(instruction.y))
                    stack.append(pc + Int(instruction.x))
                case .save: stack.append(pc + 1)
                case .assertion:
                    switch policy {
                        case .pass: stack.append(pc + 1)
                        case .keep: list.append(Int32(truncatingIfNeeded: pc))
                        case .check(let previous, let next):
                            if let kind = Assertion(rawValue: UInt8(truncatingIfNeeded: instruction.x)),
                                NeighborContext.holds(kind, previous: previous, next: next)
                            {
                                stack.append(pc + 1)
                            }
                    }
                case .byteRange, .byteSet: list.append(Int32(truncatingIfNeeded: pc))
                case .match:
                    list.append(Int32(truncatingIfNeeded: pc))
                    matched = true
                    if cutAtMatch {
                        stack.removeAll(keepingCapacity: true)
                        return true
                    }
            }
        }
        return matched
    }
}
