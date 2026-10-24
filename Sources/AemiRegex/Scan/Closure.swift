/// Epsilon-closure queries on a program, for analysis: what can consume the first byte, and which literal every match starts with.
struct Closure {
    struct Result {
        /// The byte-consuming instructions reachable without consuming input, in priority order.
        var pcs: [Int] = []
        /// Whether `match` is reachable without consuming input.
        var reachesMatch = false
    }

    private let program: Program
    private var walker: EpsilonWalker
    let hasAssertions: Bool

    init(_ program: Program) {
        self.program = program
        walker = EpsilonWalker(instructionCount: program.instructions.count)
        hasAssertions = program.instructions.contains { $0.op == .assertion }
    }

    /// The consumers reachable from `start`. An assertion is treated as true, so the result is a superset of what any real position
    /// can reach: safe for "which bytes can a match start with" and for "can the pattern match empty", never for the reverse.
    mutating func consumers(from start: Int) -> Result {
        walker.reset()
        var list: [Int32] = []
        let reachesMatch = walker.walk(
            from: start, in: program.instructions, policy: .pass, cutAtMatch: false, into: &list)
        let consumers = list.map(Int.init).filter { program.instructions[$0].op != .match }
        return Result(pcs: consumers, reachesMatch: reachesMatch)
    }

    /// Adds every byte the consumer at `pc` accepts.
    func add(_ pc: Int, to set: inout ByteSet) {
        let instruction = program.instructions[pc]
        switch instruction.op {
            case .byteRange: set.insert(UInt8(instruction.x) ... UInt8(instruction.y))
            case .byteSet: set.formUnion(program.sets[Int(instruction.x)])
            default: break
        }
    }

    /// The bytes that every match starts with, at most `maxLength` of them: follows single-byte consumers while there is exactly one.
    mutating func literalPrefix(maxLength: Int) -> [UInt8] {
        var literal: [UInt8] = []
        var start = 0
        while literal.count < maxLength {
            let step = consumers(from: start)
            guard !step.reachesMatch, step.pcs.count == 1 else { break }
            let pc = step.pcs[0]
            let instruction = program.instructions[pc]
            guard instruction.op == .byteRange, instruction.x == instruction.y else { break }
            literal.append(UInt8(instruction.x))
            start = pc + 1
        }
        return literal
    }
}
