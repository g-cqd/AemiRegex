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

    /// Set in an entry whose state needs the slow path. The sign bit marks an unbuilt transition, so one mask tests both.
    private static let tag: Int32 = 0x4000_0000
    private static let tagMask: Int32 = Int32.min | 0x4000_0000
    private static let offsetMask: Int32 = 0x3FFF_FFFF

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
    /// Whether the start states are flagged so the search consults the prefilter. A pattern without a prefilter skips that work.
    private let markStart: Bool
    /// Rows are padded to a power of two so a row offset becomes a state index with a shift.
    private let strideShift: Int
    private var stride: Int { 1 << strideShift }

    /// Transition entries: a state's row offset, `row << strideShift`, with ``tag`` set when the state needs the slow path
    /// (a match, a start state with a prefilter, or the dead state). A negative entry is a transition not built yet.
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
    init(_ program: Program, classes: ByteClasses, reverse: Bool, cacheLimit: Int, markStart: Bool = false) {
        instructions = program.instructions
        sets = program.sets
        self.classes = classes
        anchored = reverse
        longest = reverse
        usesContext = program.instructions.contains { $0.op == .assertion }
        self.cacheLimit = cacheLimit
        self.markStart = markStart
        strideShift = max(1, Int.bitWidth - (classes.count - 1).leadingZeroBitCount)
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
        table.append(contentsOf: repeatElement(Self.tag, count: stride))
        finalMatches.append(contentsOf: repeatElement(0, count: 4))
        for previous in 0 ..< 4 {
            let effective = usesContext ? previous : 0
            var key: [Int32] = [Self.header(found: false, matched: false, previous: effective)]
            walker.reset()
            sawMatch = false
            closure(0, into: &key)
            let id = intern(key, force: true) ?? 0
            if !anchored, markStart { flags[Int(id)] |= Flag.start }
            startStates.append(id)
        }
    }

    // MARK: Searching

    /// Finds the end of the leftmost-first match that starts at or after `from`.
    /// - Complexity: O(haystack size) once the states are cached; each new state costs O(program size).
    mutating func searchForward(_ haystack: UnsafeBufferPointer<UInt8>, from: Int, prefilter: Prefilter) -> Outcome {
        let count = haystack.count
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
            var byteClass = Int(classes.map[Int(unsafe haystack[position])])
            var next = table[Int(state) << strideShift + byteClass]
            if next & Self.tagMask == 0 {
                // Plain transitions in a row: leave the checked path. When the first one is already tagged (a match every few
                // bytes) the loop's setup would be wasted, which is why one step is taken before it.
                let (stopped, row) = unsafe scanForward(haystack, from: position, state: state)
                position = stopped
                state = row
                guard position < count else { break }
                byteClass = Int(classes.map[Int(unsafe haystack[position])])
                next = table[Int(state) << strideShift + byteClass]
            }
            if next < 0 {
                guard let built = transition(from: state, byteClass: byteClass) else { return .gaveUp }
                next = built
            }
            state = (next & Self.offsetMask) >> Int32(strideShift)
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
        var position = end
        var state = startStates[end == haystack.count ? NeighborContext.edge : contextOf(unsafe haystack[end])]
        var best: Int?
        while position > floor {
            var byteClass = Int(classes.map[Int(unsafe haystack[position - 1])])
            var next = table[Int(state) << strideShift + byteClass]
            if next & Self.tagMask == 0 {
                let (stopped, row) = unsafe scanBackward(haystack, from: position, floor: floor, state: state)
                position = stopped
                state = row
                guard position > floor else { break }
                byteClass = Int(classes.map[Int(unsafe haystack[position - 1])])
                next = table[Int(state) << strideShift + byteClass]
            }
            if next < 0 {
                guard let built = transition(from: state, byteClass: byteClass) else {
                    gaveUp = true
                    return nil
                }
                next = built
            }
            let nextState = (next & Self.offsetMask) >> Int32(strideShift)
            if flags[Int(nextState)] & Flag.match != 0 { best = position }
            state = nextState
            position -= 1
            if flags[Int(state)] & Flag.dead != 0 { return best }
        }
        let after = floor == 0 ? NeighborContext.edge : contextOf(unsafe haystack[floor - 1])
        if finalMatch(state, next: after) { best = floor }
        return best
    }

    // MARK: The hot loops

    /// Follows built, untagged transitions forward from `position` until the next one is tagged, unbuilt, or the text ends.
    /// - Returns: The position of the byte whose transition needs the slow path, and the state it is taken from.
    ///
    /// Memory safety: this is the only unchecked indexing in the DFA. Reads are `haystack[p]` with `p < haystack.count` (the loop
    /// guard), `classMap[byte]` with `classMap.count == 256`, and `table[row + class]` where `row` is an offset this DFA wrote
    /// (a multiple of the stride below `table.count`) and `class < classes.count <= stride`. An untagged entry is by construction
    /// the offset of a built row, and `table` is not mutated while this runs. Tests: golden, generated and agreement suites
    /// (every transition), and the sanitizer runs.
    private func scanForward(_ haystack: UnsafeBufferPointer<UInt8>, from: Int, state: Int32) -> (Int, Int32) {
        let count = haystack.count
        let shift = strideShift
        return table.withUnsafeBufferPointer { table in
            classes.map.withUnsafeBufferPointer { classMap in
                var row = Int(state) << shift
                var position = from
                while position < count {
                    let next = unsafe table[row + Int(unsafe classMap[Int(unsafe haystack[position])])]
                    if next & Self.tagMask != 0 { break }
                    row = Int(next)
                    position += 1
                }
                return (position, Int32(row >> shift))
            }
        }
    }

    /// The backward twin of ``scanForward(_:from:state:)``: reads `haystack[position - 1]` while `position > floor`.
    private func scanBackward(_ haystack: UnsafeBufferPointer<UInt8>, from: Int, floor: Int, state: Int32) -> (
        Int, Int32
    ) {
        let shift = strideShift
        return table.withUnsafeBufferPointer { table in
            classes.map.withUnsafeBufferPointer { classMap in
                var row = Int(state) << shift
                var position = from
                while position > floor {
                    let next = unsafe table[row + Int(unsafe classMap[Int(unsafe haystack[position - 1])])]
                    if next & Self.tagMask != 0 { break }
                    row = Int(next)
                    position -= 1
                }
                return (position, Int32(row >> shift))
            }
        }
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

    /// The table entry that leads to state `id`: its row offset, tagged when the state needs the slow path.
    private func entry(for id: Int32) -> Int32 {
        let offset = id << Int32(strideShift)
        return flags[Int(id)] != 0 ? offset | Self.tag : offset
    }

    /// Builds the transition from state `state` on `byteClass`. Returns the table entry for the new state, or `nil` when the cache
    /// limit stops it.
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
        let built = entry(for: id)
        table[Int(state) << strideShift + byteClass] = built
        return built
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
        let cost = stride * 4 + key.count * 4 + 128
        if !force, bytesUsed + cost > cacheLimit { return nil }
        let id = Int32(keys.count)
        keys.append(key)
        index[key] = id
        bytesUsed += cost
        table.append(contentsOf: repeatElement(-1, count: stride))
        finalMatches.append(contentsOf: repeatElement(-1, count: 4))
        var flag: UInt8 = header & 2 != 0 ? Flag.match : 0
        if isDead { flag |= Flag.dead }
        flags.append(flag)
        return id
    }
}
