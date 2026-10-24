/// A compiled regular expression.
public struct Pattern: Sendable {
    /// Limits that bound what a pattern may cost, so that attacker-supplied patterns cannot use all memory.
    public struct Limits: Equatable, Sendable {
        public var maxPatternBytes: Int
        public var maxNestingDepth: Int
        public var maxProgramSize: Int
        public var maxRepetition: Int
        public static let `default` = Limits(
            maxPatternBytes: 64 * 1024, maxNestingDepth: 250, maxProgramSize: 100_000, maxRepetition: 1000)
    }

    public init(_ pattern: String, limits: Limits = .default) throws(PatternError) {
    }

    public var captureCount: Int { 0 }

    public func groupIndex(named name: String) -> Int? { nil }

    public func firstMatch(in haystack: [UInt8], from start: Int = 0) -> Match? { nil }

    public func matches(in haystack: [UInt8]) -> [Match] { [] }
}
