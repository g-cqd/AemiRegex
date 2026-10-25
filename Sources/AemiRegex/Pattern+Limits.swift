extension Pattern {
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
}
