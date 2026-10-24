/// A lazily built DFA over a program that cannot match empty.
///
/// A state is the ordered list of program counters that would be alive in the Pike VM, plus a header: whether a match was already
/// seen (which stops new threads from starting, exactly as in the Pike VM), whether a match ended just before the byte that led
/// here, and what kind of byte that was. That makes the forward search's match end identical to the Pike VM's.
///
/// Assertions (`^ $ \b`) need the byte after the position, which a state does not know yet. They stay in the state's list as
/// pending entries and are resolved by the next transition, once the next byte is known; for the same reason a match is reported
/// one byte late. The end of the text is a final step that resolves without consuming.
///
/// States are built on first use. The cache has a byte limit, and a search that would exceed it reports ``Outcome/gaveUp`` so the
/// caller can fall back to the Pike VM instead of growing without bound.
///
/// Two modes: unanchored leftmost-first on the forward program, and anchored longest on the reversed program (which finds where a
/// match that ends at a known position begins).
struct LazyDFA {
    enum Outcome: Equatable, Sendable {
        case noMatch
        /// The end offset of the leftmost-first match.
        case match(Int)
        case gaveUp
    }

    private enum Flag {
        static let match: UInt8 = 1
        static let start: UInt8 = 2
        static let dead: UInt8 = 4
    }

    private let instructions: ContiguousArray<Instruction>
    private let sets: ContiguousArray<ByteSet>
    private let classes: ByteClasses
    private let anchored: Bool
    private let longest: Bool
    private let usesContext: Bool
    private let cacheLimit: Int

    private var table: [Int32] = []
    private var flags: [UInt8] = []
    private var keys: [[Int32]] = []
    private var index: [[Int32]: Int32] = [:]
    /// Per state and next-byte context: -1 not computed, 0 no match ends here, 1 a match ends here.
    private var finalMatches: [Int8] = []
    private var startStates: [Int32] = []
    private var bytesUsed = 0
    private var walker: EpsilonWalker
    private var live: [Int32] = []
    private var sawMatch = false

    /// Forward searches are unanchored and leftmost-first; reverse searches are anchored and longest.
    init(_ program: Program, classes: ByteClasses, reverse: Bool, cacheLimit: Int) {
        instructions = program.instructions
        sets = program.sets
        self.classes = classes
        anchored = reverse
        longest = reverse
        usesContext = program.instructions.contains { $0.op == .assertion }
        self.cacheLimit = cacheLimit
        walker = EpsilonWalker(instructionCount: program.instructions.count)
        reset()
    }

    /// Drops every state except the dead state and the start states.
    mutating func reset() {
        table.removeAll(keepingCapacity: true)
        flags.removeAll(keepingCapacity: true)
        keys.removeAll(keepingCapacity: true)
        index.removeAll(keepingCapacity: true)
        finalMatches.removeAll(keepingCapacity: true)
        startStates.removeAll(keepingCapacity: true)
        bytesUsed = 0
        keys.append([Self.header(found: true, matched: false, previous: 0)])
        flags.append(Flag.dead)
        table.append(contentsOf: repeatElement(0, count: classes.count))
        finalMatches.append(contentsOf: repeatElement(0, count: 4))
        for previous in 0 ..< 4 {
            let effective = usesContext ? previous : 0
            var key: [Int32] = [Self.header(found: false, matched: false, previous: effective)]
            walker.reset()
            sawMatch = false
            closure(0, into: &key)
            let id = intern(key, force: true) ?? 0
            if !anchored { flags[Int(id)] |= Flag.start }
            startStates.append(id)
        }
    }

    // MARK: Searching

    /// Finds the end of the leftmost-first match that starts at or after `from`.
    /// - Complexity: O(haystack size) once the states are cached; each new state costs O(program size).
    mutating func searchForward(_ haystack: UnsafeBufferPointer<UInt8>, from: Int, prefilter: Prefilter) -> Outcome {
        let count = haystack.count
        let stride = classes.count
        var position = from
        var state = startStates[unsafe previousContext(haystack, at: position)]
        var lastEnd = -1
        while true {
            if flags[Int(state)] & Flag.start != 0 {
                guard let candidate = unsafe prefilter.next(in: haystack, from: position) else { break }
                if candidate != position {
                    position = candidate
                    state = startStates[unsafe previousContext(haystack, at: position)]
                }
            }
            guard position < count else { break }
            let byteClass = Int(classes.map[Int(unsafe haystack[position])])
            var next = table[Int(state) * stride + byteClass]
            if next < 0 {
                guard let built = transition(from: state, byteClass: byteClass) else { return .gaveUp }
                next = built
            }
            state = next
            position += 1
            let flag = flags[Int(state)]
            if flag & Flag.match != 0 { lastEnd = position - 1 }
            if flag & Flag.dead != 0 { return lastEnd >= 0 ? .match(lastEnd) : .noMatch }
        }
        if position >= count, finalMatch(state, next: NeighborContext.edge) { lastEnd = count }
        return lastEnd >= 0 ? .match(lastEnd) : .noMatch
    }

    /// Finds the smallest start `>= floor` of a match that ends exactly at `end`, scanning backwards over the reversed program.
    /// - Returns: The start, or `nil` when no match ends there. `gaveUp` is set when the cache limit stopped the scan.
    mutating func searchReverse(
        _ haystack: UnsafeBufferPointer<UInt8>, end: Int, floor: Int, gaveUp: inout Bool
    ) -> Int? {
        let stride = classes.count
        var position = end
        var state = startStates[end == haystack.count ? NeighborContext.edge : contextOf(unsafe haystack[end])]
        var best: Int?
        while position > floor {
            let byteClass = Int(classes.map[Int(unsafe haystack[position - 1])])
            var next = table[Int(state) * stride + byteClass]
            if next < 0 {
                guard let built = transition(from: state, byteClass: byteClass) else {
                    gaveUp = true
                    return nil
                }
                next = built
            }
            if flags[Int(next)] & Flag.match != 0 { best = position }
            state = next
            position -= 1
            if flags[Int(state)] & Flag.dead != 0 { return best }
        }
        let after = floor == 0 ? NeighborContext.edge : contextOf(unsafe haystack[floor - 1])
        if finalMatch(state, next: after) { best = floor }
        return best
    }

    private func previousContext(_ haystack: UnsafeBufferPointer<UInt8>, at position: Int) -> Int {
        guard usesContext, position > 0, position <= haystack.count else { return 0 }
        return contextOf(unsafe haystack[position - 1])
    }

    private func contextOf(_ byte: UInt8) -> Int { usesContext ? NeighborContext.of(byte) : 0 }

    // MARK: Building states

    private static func header(found: Bool, matched: Bool, previous: Int) -> Int32 {
        (found ? 1 : 0) | (matched ? 2 : 0) | Int32(previous << 2)
    }

    /// Whether a match ends at the position this state stands for, given what the next byte is.
    private mutating func finalMatch(_ state: Int32, next: Int) -> Bool {
        let slot = Int(state) * 4 + (usesContext ? next : 0)
        if finalMatches[slot] < 0 {
            let key = keys[Int(state)]
            let previous = Int(key[0] >> 2) & 3
            finalMatches[slot] = resolve(key, previous: previous, next: next) ? 1 : 0
        }
        return finalMatches[slot] == 1
    }

    /// Resolves the pending assertions of `key` for the given neighbours, leaving the consumers and any match in ``live``.
    /// - Returns: Whether a match is among them.
    private mutating func resolve(_ key: [Int32], previous: Int, next: Int) -> Bool {
        walker.reset()
        live.removeAll(keepingCapacity: true)
        sawMatch = false
        for slot in 1 ..< key.count {
            let matched = walker.walk(
                from: Int(key[slot]), in: instructions, policy: .check(previous: previous, next: next),
                cutAtMatch: !longest, into: &live)
            sawMatch = sawMatch || matched
            if sawMatch, !longest { return true }
        }
        return sawMatch
    }

    private mutating func transition(from state: Int32, byteClass: Int) -> Int32? {
        let key = keys[Int(state)]
        let byte = classes.representatives[byteClass]
        let previous = Int(key[0] >> 2) & 3
        let nextContext = usesContext ? Int(classes.contexts[byteClass]) : 0
        let matched = resolve(key, previous: previous, next: nextContext)
        let found = key[0] & 1 != 0 || matched

        var successor: [Int32] = [0]
        walker.reset()
        sawMatch = false
        for pc32 in live {
            let pc = Int(pc32)
            let instruction = instructions[pc]
            switch instruction.op {
                case .match:
                    break  // leftmost-first: the loop ends below, which drops every lower-priority thread
                case .byteRange:
                    if byte >= UInt8(instruction.x), byte <= UInt8(instruction.y) { closure(pc + 1, into: &successor) }
                case .byteSet:
                    if sets[Int(instruction.x)].contains(byte) { closure(pc + 1, into: &successor) }
                case .split, .jump, .save, .assertion:
                    break
            }
            if instruction.op == .match, !longest { break }
            if sawMatch, !longest { break }
        }
        if !anchored, !found, !sawMatch { closure(0, into: &successor) }
        successor[0] = Self.header(found: found, matched: matched, previous: nextContext)
        guard let id = intern(successor, force: false) else { return nil }
        table[Int(state) * classes.count + byteClass] = id
        return id
    }

    /// Adds the consumers, the match and the pending assertions reachable from `start`, in priority order. Assertions are kept,
    /// not resolved: the next byte is not known yet.
    private mutating func closure(_ start: Int, into list: inout [Int32]) {
        if sawMatch, !longest { return }
        let matched = walker.walk(from: start, in: instructions, policy: .keep, cutAtMatch: !longest, into: &list)
        sawMatch = sawMatch || matched
    }

    /// The id of the state with this key, creating it. `nil` when the cache would exceed its limit.
    private mutating func intern(_ key: [Int32], force: Bool) -> Int32? {
        let header = key[0]
        let isDead = key.count == 1 && (header & 1 != 0 || anchored)
        if isDead, header & 2 == 0 { return 0 }
        if let existing = index[key] { return existing }
        let cost = classes.count * 4 + key.count * 4 + 128
        if !force, bytesUsed + cost > cacheLimit { return nil }
        let id = Int32(keys.count)
        keys.append(key)
        index[key] = id
        bytesUsed += cost
        table.append(contentsOf: repeatElement(-1, count: classes.count))
        finalMatches.append(contentsOf: repeatElement(-1, count: 4))
        var flag: UInt8 = header & 2 != 0 ? Flag.match : 0
        if isDead { flag |= Flag.dead }
        flags.append(flag)
        return id
    }
}
