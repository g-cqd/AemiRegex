/// A regular expression run by a backtracking engine: the constructs the default engine cannot run in linear time, namely backreferences,
/// lookahead, lookbehind, atomic groups and possessive quantifiers, in ECMAScript or PCRE2 syntax.
///
/// A search can take exponential time for some pattern and text, so it runs under a ``Budget`` and throws
/// ``BacktrackError/budgetExceeded(_:)`` instead of hanging. Use ``Pattern`` when the pattern needs none of these constructs.
public struct BacktrackingPattern: Sendable {
    /// The syntax and semantics a pattern follows.
    public enum Dialect: Equatable, Sendable {
        /// ECMAScript with the `u` flag (code points): `node`'s `RegExp` is the oracle.
        case ecmaScript
        /// PCRE2 in UTF mode without UCP (`\d \w \s` are ASCII): `libpcre2` is the oracle.
        case pcre2
    }

    /// What one search may cost. Both limits bound a single call of a search method.
    public struct Budget: Equatable, Sendable {
        /// The most instructions one call may execute.
        public var maxSteps: Int
        /// The most choice points and undo records one call may hold at once; 24 bytes each.
        public var maxStackEntries: Int
        /// The deepest nesting of subroutine calls and recursion (PCRE2 `(?1)`, `(?R)`); each level keeps a copy of the capture slots.
        public var maxRecursionDepth: Int

        public init(maxSteps: Int, maxStackEntries: Int, maxRecursionDepth: Int = 250) {
            self.maxSteps = maxSteps
            self.maxStackEntries = maxStackEntries
            self.maxRecursionDepth = maxRecursionDepth
        }

        public static let `default` = Budget(maxSteps: 10_000_000, maxStackEntries: 1 << 20)
    }

    /// Compiles `pattern`.
    ///
    /// - Parameters:
    ///   - pattern: The pattern text.
    ///   - dialect: The syntax it is written in.
    ///   - options: The flags that apply to the whole pattern.
    ///   - limits: What the pattern may cost to compile; the same limits as ``Pattern``.
    ///   - budget: What each search may cost.
    /// - Throws: ``PatternError`` with the offset in `pattern`, or `.unsupported` for a construct this engine does not run yet.
    public init(
        _ pattern: String, dialect: Dialect, options: Options = [], limits: Pattern.Limits = .default,
        budget: Budget = .default
    ) throws(PatternError) {
        let tree = try BTParser.parse(pattern, dialect: dialect, options: options, limits: limits)
        program = try BTCompiler.compile(tree, dialect: dialect, limits: limits)
        self.budget = budget
    }

    let program: BTProgram
    let budget: Budget

    /// The number of capture groups, not counting the whole match.
    public var captureCount: Int { program.captureCount }

    /// The index of the first group named `name`, or `nil` when there is none.
    public func groupIndex(named name: String) -> Int? { program.names[name]?.first }

    /// The indices of every group named `name`: more than one only in ECMAScript, where a name may repeat in different alternatives.
    public func groupIndices(named name: String) -> [Int] { program.names[name] ?? [] }

    /// The leftmost match that starts at or after byte offset `start`, or `nil`.
    ///
    /// Backtracking tries each alternative in order, so the match is the one Perl, PCRE2 and ECMAScript report, not the leftmost-longest.
    /// Bytes that are not valid UTF-8 are never matched by a class or `.`.
    /// - Parameters:
    ///   - haystack: The bytes to search.
    ///   - start: A UTF-8 byte offset in `0 ... haystack.count`; any other value gives `nil`.
    /// - Returns: The match, or `nil` when there is none.
    /// - Throws: ``BacktrackError/budgetExceeded(_:)`` when the search uses up its ``Budget``.
    /// - Complexity: Exponential in the worst case, bounded by ``Budget/maxSteps``.
    public func firstMatch(in haystack: [UInt8], from start: Int = 0) throws(BacktrackError) -> Match? {
        try search(haystack) { machine, bytes throws(BacktrackError) in try machine.firstMatch(in: bytes, from: start) }
    }
}
