/// A compiled regular expression.
///
/// The syntax is RE2's: no backreferences and no lookaround, which is what lets every search run in time proportional to
/// the pattern times the input. A pattern is a value: compile it once, then match from any task.
public struct Pattern: Sendable {
    let program: Program
    let prefilter: Prefilter
    let literals: LiteralSet?
    /// The byte every match ends with and nothing else consumes, so a search can jump between its occurrences (see ``TerminalByte``).
    let terminalByte: UInt8?
    /// Whether searches jump between occurrences of ``terminalByte``: it has one, and no prefix or literal set guides the search better.
    let jumpsToTerminalByte: Bool
    let plan: DFAPlan?
    let pool: ScratchPool

    /// Compiles `pattern`.
    /// - Throws: ``PatternError`` for malformed syntax, an unsupported construct, or a pattern over a limit.
    public init(_ pattern: String, limits: Limits = .default) throws(PatternError) {
        try self.init(pattern, limits: limits, engine: .automatic)
    }

    init(
        _ pattern: String, limits: Limits = .default, engine: Engine, wholeString: Bool = false
    ) throws(PatternError) {
        let program = try Parser.compile(
            pattern, limits: limits, wholeString: wholeString)
        let plan = try Self.makePlan(
            pattern, program, limits: limits, engine: engine, wholeString: wholeString)
        self.program = program
        self.plan = plan
        endAnchored = plan != nil && DFAPlan.isEndAnchored(program)
        let prefilter = plan == nil ? Prefilter(.none) : Prefilter(analyzing: program)
        self.prefilter = prefilter
        let markStart = prefilter.kind != .none
        literals = plan == nil || !markStart ? nil : LiteralSet(program)
        terminalByte = plan == nil ? nil : TerminalByte.find(in: program)
        // A prefix the prefilter can skip to is the better guide, so the jump serves only the patterns without one.
        jumpsToTerminalByte = terminalByte != nil && !markStart && literals == nil
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
        _ pattern: String, _ program: Program, limits: Limits, engine: Engine, wholeString: Bool
    ) throws(PatternError) -> DFAPlan? {
        guard engine == .automatic, DFAPlan.isEligible(program) else { return nil }
        let reverse = try Parser.compile(
            pattern, limits: limits, reverse: true, wholeString: wholeString)
        return DFAPlan(reverse: reverse, forwardClasses: ByteClasses(program), reverseClasses: ByteClasses(reverse))
    }

    /// Compiles `pattern` in `syntax`.
    ///
    /// - Parameters:
    ///   - pattern: The pattern text.
    ///   - syntax: The dialect the pattern is written in.
    ///   - matching: `.wholeString` requires a match to be the entire text; `.search` finds one anywhere. The default is the dialect's:
    ///     whole-string for I-Regexp, search for RE2.
    ///   - limits: What the pattern may cost.
    /// - Throws: ``PatternError``, with the offset in `pattern` as written.
    public init(_ pattern: String, syntax: Syntax, matching: Matching? = nil, limits: Limits = .default)
        throws(PatternError)
    {
        let source: String
        switch syntax {
            case .re2: source = pattern
            case .iRegexp: source = try IRegexp.translate(pattern, limits: limits)
            case .iRegexpWithAnchors: source = try IRegexp.translate(pattern, limits: limits, anchors: true)
        }
        let whole = (matching ?? (syntax == .re2 ? .search : .wholeString)) == .wholeString
        try self.init(source, limits: limits, engine: .automatic, wholeString: whole)
    }

    /// The number of capture groups, not counting the whole match.
    public var captureCount: Int { program.captureCount }

    /// The index of the group named `name`, or `nil` when there is none.
    public func groupIndex(named name: String) -> Int? { program.names[name] }

    /// How many searches each engine has answered, for the scratch most recently used.
    var searchCounts: SearchCounts { pool.withScratch { $0.counts } }

    /// Whether every match must end at the end of the text, so a search can run backwards from the end.
    let endAnchored: Bool

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
        haystack.withUnsafeBufferPointer { unsafe firstMatch(inBuffer: ByteBuffer($0), from: start) }
    }

    /// Every non-overlapping match, left to right. An empty match that touches the previous match is skipped, as in RE2 and Go.
    /// - Parameter haystack: The bytes to search.
    /// - Returns: The matches in order; empty when there are none.
    /// - Complexity: As ``firstMatch(in:from:)`` in total, with one scratch value for all matches.
    public func matches(in haystack: [UInt8]) -> [Match] {
        var result: [Match] = []
        forEachMatch(in: haystack) { match in
            result.append(match)
            return true
        }
        return result
    }

    /// Calls `body` with each match, left to right, as ``matches(in:)`` would list them, without building the list.
    /// - Parameters:
    ///   - haystack: The bytes to search.
    ///   - body: Receives a match; return `false` to stop.
    /// - Complexity: As ``matches(in:)``; allocates nothing per match for a pattern without capture groups.
    public func forEachMatch(in haystack: [UInt8], _ body: (Match) -> Bool) {
        haystack.withUnsafeBufferPointer { unsafe forEachMatch(inBuffer: ByteBuffer($0), body) }
    }

    /// The number of matches ``matches(in:)`` would list, counted without building them.
    public func matchCount(in haystack: [UInt8]) -> Int {
        var count = 0
        haystack.withUnsafeBufferPointer { buffer in
            unsafe forEachMatch(inBuffer: ByteBuffer(buffer), needsCaptures: false) { _ in
                count += 1
                return true
            }
        }
        return count
    }

    /// Whether there is a match. For a whole-string pattern: whether the whole text is one.
    public func isMatch(in haystack: [UInt8]) -> Bool {
        haystack.withUnsafeBufferPointer {
            unsafe firstMatch(inBuffer: ByteBuffer($0), from: 0, needsCaptures: false) != nil
        }
    }

    /// What the forward DFA says about `haystack`, for tests of the cache limit.
    func forwardOutcome(in haystack: [UInt8]) -> LazyDFA.Outcome {
        haystack.withUnsafeBufferPointer { unsafe forwardOutcome(inBuffer: $0) }
    }

    /// The forward DFA over a buffer the caller controls, so a test can put bytes just past its end and see whether they are read.
    func forwardOutcome(inBuffer buffer: UnsafeBufferPointer<UInt8>) -> LazyDFA.Outcome {
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
}
