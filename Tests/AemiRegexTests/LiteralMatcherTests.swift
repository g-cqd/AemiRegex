import Testing

@testable import AemiRegex

/// A pattern that is only an alternation of fixed strings (each position a byte or a small set of bytes) is matched by verifying the
/// strings at prefilter candidates: no DFA, no reverse scan. Alternation order is priority order, as in every leftmost-first engine.
struct LiteralMatcherTests {
    @Test(arguments: [
        ("Sendable", true), ("import|struct|enum", true), ("(?i)todo|fixme|hack", true), ("a|ab", true), ("é|e", true),
        ("[ab]c", true), ("(?i)straSSe", true),
        ("(a)|b", false), ("a*b", false), ("[a-z]+", false), ("^abc", false), (#"\bfoo"#, false), ("a|", false),
        ("", false),
        ("[a-z]x", false), ("a{2,3}", true), ("a+", false)
    ])
    func `only an alternation of short fixed strings with no captures uses the literal matcher`(
        source: String, eligible: Bool
    ) throws {
        #expect(try Pattern(source).usesLiteralMatcher == eligible)
    }

    @Test func `an alternation of more than the supported number of literals falls back to the DFA`() throws {
        let many = (0 ..< 100).map { "word\($0)" }.joined(separator: "|")
        let pattern = try Pattern(many)
        #expect(!pattern.usesLiteralMatcher)
        #expect(
            pattern.firstMatch(in: Array("xx word57 yy".utf8))?.range == 3 ..< 8,
            "word5 is an earlier alternative than word57")
    }

    struct Case: Sendable, CustomTestStringConvertible {
        let pattern: String
        let haystack: String
        let range: Range<Int>?
        var testDescription: String { "/\(pattern)/ on \(haystack.debugDescription)" }
    }

    static let cases: [Case] = [
        Case(pattern: "a|ab", haystack: "ab", range: 0 ..< 1),
        Case(pattern: "ab|a", haystack: "ab", range: 0 ..< 2),
        Case(pattern: "bc|abc", haystack: "abc", range: 0 ..< 3),
        Case(pattern: "abc|bc", haystack: "xbc", range: 1 ..< 3),
        Case(pattern: "é|ü", haystack: "aüé", range: 1 ..< 3),
        Case(pattern: "(?i)todo|fixme", haystack: "x FixMe y", range: 2 ..< 7),
        Case(pattern: "aa|aab", haystack: "aab", range: 0 ..< 2),
        Case(pattern: "abc|abd", haystack: "ab", range: nil),
        Case(pattern: "abc|abd", haystack: "abab", range: nil),
        Case(pattern: "abc", haystack: "ababc", range: 2 ..< 5)
    ]

    @Test(arguments: cases)
    func `the literal matcher gives the leftmost match, and among alternatives at one start the earliest`(case c: Case)
        throws
    {
        let pattern = try Pattern(c.pattern)
        #expect(pattern.usesLiteralMatcher)
        #expect(pattern.firstMatch(in: Array(c.haystack.utf8))?.range == c.range)
    }

    @Test func `a candidate that cannot be verified because the text ends first is not a match and not a crash`() throws
    {
        let pattern = try Pattern("abcdef|xyz")
        #expect(pattern.firstMatch(in: Array("abcde".utf8)) == nil)
        #expect(pattern.firstMatch(in: Array("xy".utf8)) == nil)
        #expect(pattern.matches(in: Array("zzabcdefxyzxy".utf8)).map(\.range) == [2 ..< 8, 8 ..< 11])
    }

    @Test func `an eligible pattern is answered by the literal matcher and by nothing else`() throws {
        let pattern = try Pattern("import|struct|enum")
        _ = pattern.firstMatch(in: Array("a struct b".utf8))
        _ = pattern.matches(in: Array("import x; enum y".utf8))
        #expect(pattern.searchCounts == SearchCounts(literal: 4, dfa: 0, pike: 0))
    }

    @Test func `a pattern that is not a literal set is answered by the DFA, and the reference engine by the Pike VM`()
        throws
    {
        let text = Array("ab12 cd34".utf8)
        let automatic = try Pattern("[a-z]+[0-9]+")
        _ = automatic.firstMatch(in: text)
        #expect(automatic.searchCounts == SearchCounts(literal: 0, dfa: 1, pike: 0))
        let reference = try Pattern("import|struct|enum", engine: .pikeOnly)
        _ = reference.firstMatch(in: Array("struct".utf8))
        #expect(reference.searchCounts == SearchCounts(literal: 0, dfa: 0, pike: 1))
    }

    /// Many candidates that all fail verification, then one match far away: the windowed scan must keep going, grow its window, and
    /// still find the match at the right place, including when the match sits right at a window boundary.
    @Test(arguments: [0, 1, 255, 256, 257, 511, 512, 1023, 1024, 5000, 100_000])
    func `a match after a long run of rejected candidates is found at the right offset`(gap: Int) throws {
        let pattern = try Pattern("struct|enum|class")
        #expect(pattern.usesLiteralMatcher)
        // "st", "en" and "cl" are candidate pairs, but "stx", "enx" and "clx" never complete a literal.
        let filler = Array("stx enx clx ".utf8)
        var text: [UInt8] = []
        while text.count < gap { text += filler }
        text = Array(text.prefix(gap))
        let match = Array("class".utf8)
        let haystack = text + match + Array(" tail stx".utf8)
        #expect(pattern.firstMatch(in: haystack)?.range == gap ..< gap + 5)
        #expect(pattern.matches(in: haystack).map(\.range) == [gap ..< gap + 5])
    }

    @Test func `matches spaced from a few bytes to a few kilobytes apart are all found once`() throws {
        let pattern = try Pattern("import|struct|enum")
        var text: [UInt8] = []
        var expected: [Range<Int>] = []
        let words = ["import", "struct", "enum"]
        var rng = SplitMix64(state: 0x51ACED)
        for _ in 0 ..< 300 {
            let spacing = [1, 7, 60, 400, 3000].randomElement(using: &rng) ?? 1
            text += [UInt8](repeating: 0x2E, count: spacing)
            let name: String = words.randomElement(using: &rng) ?? "enum"
            let word = Array(name.utf8)
            expected.append(text.count ..< text.count + word.count)
            text += word
        }
        #expect(pattern.matches(in: text).map(\.range) == expected)
    }
}
