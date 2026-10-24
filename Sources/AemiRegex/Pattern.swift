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

        public static let `default` = Limits(
            maxPatternBytes: 64 * 1024, maxNestingDepth: 250, maxProgramSize: 100_000, maxRepetition: 1000)
    }

    let program: Program

    /// Compiles `pattern`.
    /// - Throws: ``PatternError`` for malformed syntax, an unsupported construct, or a pattern over a limit.
    public init(_ pattern: String, limits: Limits = .default) throws(PatternError) {
        program = try Parser.compile(pattern, limits: limits)
    }

    /// The number of capture groups, not counting the whole match.
    public var captureCount: Int { program.captureCount }

    /// The index of the group named `name`, or `nil` when there is none.
    public func groupIndex(named name: String) -> Int? { program.names[name] }

    /// The leftmost match that starts at or after byte offset `start`, or `nil`.
    ///
    /// Assertions such as `^` and `\b` see the bytes before `start`. Bytes that are not valid UTF-8 never match a class or `.`.
    /// - Parameters:
    ///   - haystack: The bytes to search.
    ///   - start: A UTF-8 byte offset in `0 ... haystack.count`; any other value gives `nil`.
    /// - Returns: The match, or `nil` when there is none.
    /// - Complexity: O(pattern size × haystack size).
    public func firstMatch(in haystack: [UInt8], from start: Int = 0) -> Match? {
        guard start >= 0, start <= haystack.count else { return nil }
        var machine = PikeVM(program)
        return Self.match(&machine, haystack, from: start)
    }

    /// Every non-overlapping match, left to right. An empty match that touches the previous match is skipped, as in RE2 and Go.
    /// - Parameter haystack: The bytes to search.
    /// - Returns: The matches in order; empty when there are none.
    /// - Complexity: O(pattern size × haystack size) in total, with one set of scratch buffers for all matches.
    public func matches(in haystack: [UInt8]) -> [Match] {
        var machine = PikeVM(program)
        var result: [Match] = []
        var position = 0
        var previousEnd = -1
        while position <= haystack.count, let match = Self.match(&machine, haystack, from: position) {
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

    private static func match(_ machine: inout PikeVM, _ haystack: [UInt8], from start: Int) -> Match? {
        guard machine.search(haystack, from: start) else { return nil }
        let slots = machine.best
        let groups = (0 ..< slots.count / 2)
            .map { group -> Range<Int>? in
                let lower = slots[2 * group]
                let upper = slots[2 * group + 1]
                return lower >= 0 && upper >= lower ? lower ..< upper : nil
            }
        return Match(groups: groups)
    }
}
