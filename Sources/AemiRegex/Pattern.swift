/// A compiled regular expression.
///
/// The syntax is RE2's: no backreferences and no lookaround, which is what lets every search run in time proportional to
/// the pattern times the input. A pattern is a value: compile it once, then match from any task.
public struct Pattern: Sendable {
    /// Limits that bound what a pattern may cost, so that an attacker-supplied pattern cannot use all memory.
    public struct Limits: Equatable, Sendable {
        public var maxPatternBytes: Int
        public var maxNestingDepth: Int
        public var maxProgramSize: Int
        public var maxRepetition: Int
        public var maxCaptureGroups = 1000
        /// Bound on instructions × capture slots, the size of one thread table. A search holds two, each of `Int` entries,
        /// so the default (4M entries) caps the scratch memory at 64 MB however the pattern is shaped.
        public var maxThreadTableEntries = 1 << 22
        /// Bound on one lazy DFA's cache. A pattern holds up to two DFAs (forward and reverse) per concurrent search. A search that
        /// would exceed it falls back to the Pike VM, which is slower and uses no cache.
        public var maxDFACacheBytes = 2 << 20

        public static let `default` = Limits(
            maxPatternBytes: 64 * 1024, maxNestingDepth: 250, maxProgramSize: 100_000, maxRepetition: 1000)
    }

    /// Which engines may run. The Pike VM alone is the reference the DFA pipeline is tested against.
    enum Engine: Sendable {
        case automatic
        case pikeOnly
    }

    let program: Program
    let prefilter: Prefilter
    private let literals: LiteralSet?
    private let plan: DFAPlan?
    private let pool: ScratchPool

    /// Compiles `pattern`.
    /// - Throws: ``PatternError`` for malformed syntax, an unsupported construct, or a pattern over a limit.
    public init(_ pattern: String, limits: Limits = .default) throws(PatternError) {
        try self.init(pattern, limits: limits, engine: .automatic)
    }

    init(_ pattern: String, limits: Limits = .default, engine: Engine) throws(PatternError) {
        let program = try Parser.compile(pattern, limits: limits)
        let plan = try Self.makePlan(pattern, program, limits: limits, engine: engine)
        self.program = program
        self.plan = plan
        let prefilter = plan == nil ? Prefilter(.none) : Prefilter(analyzing: program)
        self.prefilter = prefilter
        let markStart = prefilter.kind != .none
        literals = plan == nil || !markStart ? nil : LiteralSet(program)
        let cacheLimit = limits.maxDFACacheBytes
        pool = ScratchPool {
            SearchScratch(
                forward: plan.map {
                    LazyDFA(
                        program, classes: $0.forwardClasses, reverse: false, cacheLimit: cacheLimit,
                        markStart: markStart)
                },
                reverse: plan.map {
                    LazyDFA($0.reverse, classes: $0.reverseClasses, reverse: true, cacheLimit: cacheLimit)
                },
                pike: PikeVM(program))
        }
    }

    private static func makePlan(
        _ pattern: String, _ program: Program, limits: Limits, engine: Engine
    ) throws(PatternError) -> DFAPlan? {
        guard engine == .automatic else { return nil }
        let reverse = try Parser.compile(pattern, limits: limits, reverse: true)
        return DFAPlan(reverse: reverse, forwardClasses: ByteClasses(program), reverseClasses: ByteClasses(reverse))
    }

    /// The number of capture groups, not counting the whole match.
    public var captureCount: Int { program.captureCount }

    /// The index of the group named `name`, or `nil` when there is none.
    public func groupIndex(named name: String) -> Int? { program.names[name] }

    /// How many searches each engine has answered, for the scratch most recently used.
    var searchCounts: SearchCounts { pool.withScratch { $0.counts } }

    /// Whether searches use the literal matcher: the pattern is an alternation of short fixed strings.
    var usesLiteralMatcher: Bool { literals != nil }

    /// Whether searches run through the DFA pipeline (every pattern does, unless the Pike VM is forced).
    var usesDFA: Bool { plan != nil }

    /// The leftmost match that starts at or after byte offset `start`, or `nil`.
    ///
    /// Assertions such as `^` and `\b` see the bytes before `start`. Bytes that are not valid UTF-8 never match a class or `.`.
    /// - Parameters:
    ///   - haystack: The bytes to search.
    ///   - start: A UTF-8 byte offset in `0 ... haystack.count`; any other value gives `nil`.
    /// - Returns: The match, or `nil` when there is none.
    /// - Complexity: O(pattern size × haystack size) worst case; O(haystack size) once the DFA has built its states.
    public func firstMatch(in haystack: [UInt8], from start: Int = 0) -> Match? {
        guard start >= 0, start <= haystack.count else { return nil }
        var allowDFA = true
        return pool.withScratch { search(&$0, haystack, from: start, allowDFA: &allowDFA) }
    }

    /// Every non-overlapping match, left to right. An empty match that touches the previous match is skipped, as in RE2 and Go.
    /// - Parameter haystack: The bytes to search.
    /// - Returns: The matches in order; empty when there are none.
    /// - Complexity: As ``firstMatch(in:from:)`` in total, with one scratch value for all matches.
    public func matches(in haystack: [UInt8]) -> [Match] {
        pool.withScratch { scratch in
            var result: [Match] = []
            var position = 0
            var previousEnd = -1
            var allowDFA = true
            while position <= haystack.count,
                let match = search(&scratch, haystack, from: position, allowDFA: &allowDFA)
            {
                var accept = true
                if match.range.upperBound == position {
                    if match.range.lowerBound == previousEnd { accept = false }
                    position += position < haystack.count ? Utf8.width(of: haystack, at: position) : 1
                } else {
                    position = match.range.upperBound
                }
                previousEnd = match.range.upperBound
                if accept { result.append(match) }
            }
            return result
        }
    }

    /// What the forward DFA says about `haystack`, for tests of the cache limit.
    func forwardOutcome(in haystack: [UInt8]) -> LazyDFA.Outcome {
        haystack.withUnsafeBufferPointer { unsafe forwardOutcome(in: $0) }
    }

    /// The forward DFA over a buffer the caller controls, so a test can put bytes just past its end and see whether they are read.
    func forwardOutcome(in buffer: UnsafeBufferPointer<UInt8>) -> LazyDFA.Outcome {
        pool.withScratch { scratch in
            let outcome = unsafe scratch.forward?.searchForward(buffer, from: 0, prefilter: prefilter)
            if outcome == .gaveUp { scratch.forward?.reset() }
            return outcome ?? .noMatch
        }
    }

    /// The reverse DFA over a buffer the caller controls: the start of a match ending at `end`, scanning down to `floor` only.
    func reverseStart(in buffer: UnsafeBufferPointer<UInt8>, end: Int, floor: Int) -> Int? {
        pool.withScratch { scratch in
            var gaveUp = false
            return unsafe scratch.reverse?.searchReverse(buffer, end: end, floor: floor, gaveUp: &gaveUp)
        }
    }

    // MARK: Search

    /// One search: the DFA finds where the match ends and where it starts, and the Pike VM runs on that window only if the
    /// pattern has captures. A DFA that gives up (cache full) disables itself for the rest of the call and the Pike VM answers.
    ///
    /// The DFA starts a match at every byte, the Pike VM only at scalar boundaries. A match that begins with a byte cannot start
    /// inside a scalar, so the two differ only for an empty match inside one; such a match is dropped and the search resumes at the
    /// next byte, which is what the Pike VM would have done (at most three retries per scalar).
    private func search(_ scratch: inout SearchScratch, _ haystack: [UInt8], from start: Int, allowDFA: inout Bool)
        -> Match?
    {
        if let literals {
            scratch.counts.literal += 1
            return literalSearch(literals, haystack, from: start)
        }
        if allowDFA, scratch.forward != nil {
            scratch.counts.dfa += 1
            var from = start
            while from <= haystack.count {
                let outcome = haystack.withUnsafeBufferPointer {
                    unsafe scratch.forward?.searchForward($0, from: from, prefilter: prefilter)
                }
                guard case .match(let end) = outcome else {
                    if outcome == .noMatch { return nil }
                    scratch.forward?.reset()
                    break
                }
                var gaveUp = false
                let matchStart = haystack.withUnsafeBufferPointer {
                    unsafe scratch.reverse?.searchReverse($0, end: end, floor: from, gaveUp: &gaveUp)
                }
                guard let matchStart else {
                    if gaveUp { scratch.reverse?.reset() }
                    break
                }
                if matchStart == end, !PikeVM.isBoundary(haystack, matchStart) {
                    from = matchStart + 1
                    continue
                }
                if program.captureCount == 0 { return Match(range: matchStart ..< end) }
                return pike(&scratch, haystack, from: matchStart, anchored: true, limit: end)
            }
            if from > haystack.count { return nil }
            allowDFA = false
        }
        return pike(&scratch, haystack, from: start, anchored: false, limit: nil)
    }

    /// The leftmost match of a pure literal alternation: the prefilter offers candidates and the alternatives are checked at each.
    private func literalSearch(_ literals: LiteralSet, _ haystack: [UInt8], from start: Int) -> Match? {
        haystack.withUnsafeBufferPointer { buffer in
            unsafe literals.firstMatch(in: buffer, from: start, prefilter: prefilter).map { Match(range: $0) }
        }
    }

    private func pike(_ scratch: inout SearchScratch, _ haystack: [UInt8], from start: Int, anchored: Bool, limit: Int?)
        -> Match?
    {
        scratch.counts.pike += 1
        guard scratch.pike.search(haystack, from: start, anchored: anchored, limit: limit) else { return nil }
        let slots = scratch.pike.best
        let captures = (1 ..< slots.count / 2)
            .map { group -> Range<Int>? in
                let lower = slots[2 * group]
                let upper = slots[2 * group + 1]
                return lower >= 0 && upper >= lower ? lower ..< upper : nil
            }
        return Match(range: slots[0] ..< slots[1], captures: captures)
    }
}
