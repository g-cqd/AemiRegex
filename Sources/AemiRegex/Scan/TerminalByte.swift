internal import AemiKernel

/// The byte that every match of a pattern ends with and that nothing else in the pattern can consume.
///
/// Such a byte lets a search jump from one occurrence to the next instead of scanning every byte. No match can contain two of them, so
/// the first occurrence after the start is the only place the leftmost match can end, and a match that ends there starts at the leftmost
/// position a reverse search reaches. A later occurrence can only end a match that starts after this one.
enum TerminalByte {
    /// Patterns with more than this many final consumers are not analysed: each one costs a closure walk.
    private static let maxFinals = 64

    /// The terminal byte of the pattern, or `nil` when it has none.
    ///
    /// The byte qualifies when all of this holds, treating every assertion as true (a superset, so a doubt disqualifies):
    /// 1. `match` cannot be reached without consuming a byte, so no match is empty;
    /// 2. each instruction that can be the last to consume (a *final*) is followed by nothing that consumes, so it ends the match;
    /// 3. the finals accept exactly one byte, the same one, and it is ASCII, so the position after it is a scalar boundary;
    /// 4. no other instruction accepts that byte, so it occurs once per match.
    /// - Complexity: O(instructions) for the reachability pass plus one closure walk per final.
    static func find(in program: Program) -> UInt8? {
        let code = program.instructions
        let reaching = reachesMatchWithoutConsuming(program)
        guard !reaching[0] else { return nil }
        var closure = Closure(program)
        var finals: [Int] = []
        for pc in code.indices where isConsumer(code[pc]) && reaching[pc + 1] {
            guard closure.consumers(from: pc + 1).pcs.isEmpty, finals.count < maxFinals else { return nil }
            finals.append(pc)
        }
        var accepted = ByteBitmap()
        for pc in finals { closure.add(pc, to: &accepted) }
        let bytes = accepted.members
        guard bytes.count == 1, let byte = bytes.first, byte < 0x80 else { return nil }
        let isFinal = Set(finals)
        for pc in code.indices where isConsumer(code[pc]) && !isFinal.contains(pc) {
            var set = ByteBitmap()
            closure.add(pc, to: &set)
            if set.contains(byte) { return nil }
        }
        return byte
    }

    private static func isConsumer(_ instruction: Instruction) -> Bool {
        instruction.op == .byteRange || instruction.op == .byteSet
    }

    /// For each instruction (and one past the end), whether `match` is reachable from it through save, jump, split and assertion
    /// instructions only.
    private static func reachesMatchWithoutConsuming(_ program: Program) -> [Bool] {
        let code = program.instructions
        let predecessors = program.predecessors(includingConsuming: false)
        var reaching = [Bool](repeating: false, count: code.count + 1)
        var work: [Int] = []
        for pc in code.indices where code[pc].op == .match {
            reaching[pc] = true
            work.append(pc)
        }
        while let pc = work.popLast() {
            for before in predecessors[pc] where !reaching[before] {
                reaching[before] = true
                work.append(before)
            }
        }
        return reaching
    }
}
