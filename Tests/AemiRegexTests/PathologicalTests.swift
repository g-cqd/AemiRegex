import Testing

@testable import AemiRegex

/// A backtracking engine takes exponential time on these. The ceiling is generous (shared CI) but far below exponential.
struct PathologicalTests {
    private static let ceiling = Duration.seconds(2)

    struct Case: Sendable, CustomTestStringConvertible {
        let pattern: String
        let haystack: [UInt8]
        let matches: Bool
        /// A haystack of the same size that the pattern does match: a positive control, so that "no match" cannot be a stub.
        let control: [UInt8]
        var testDescription: String { "/\(pattern)/ on \(haystack.count) bytes" }
    }

    private static let cases: [Case] = {
        let a = [UInt8](repeating: UInt8(ascii: "a"), count: 100_000)
        let x = [UInt8](repeating: UInt8(ascii: "x"), count: 100_000)
        let b = UInt8(ascii: "b")
        return [
            Case(pattern: "(a+)+b", haystack: a, matches: false, control: a + [b]),
            Case(pattern: "(a*)*b", haystack: a, matches: false, control: a + [b]),
            Case(pattern: "(a|aa)+$", haystack: a + [b], matches: false, control: a),
            Case(pattern: "(a?){30}a{30}", haystack: Array(a.prefix(30)), matches: true, control: Array(a.prefix(30))),
            Case(pattern: "(x+x+)+y", haystack: x, matches: false, control: x + [UInt8(ascii: "y")]),
            Case(pattern: "(.*)(.*)(.*)(.*)(.*)z", haystack: a, matches: false, control: a + [UInt8(ascii: "z")])
        ]
    }()

    @Test(arguments: cases)
    func `matching time is bounded for a pattern that makes a backtracking engine explode`(case c: Case) throws {
        let pattern = try Pattern(c.pattern)
        let clock = ContinuousClock()
        var found = false
        let elapsed = clock.measure { found = pattern.firstMatch(in: c.haystack) != nil }
        #expect(found == c.matches)
        #expect(pattern.firstMatch(in: c.control) != nil, "the control haystack must match")
        #expect(elapsed < Self.ceiling, "took \(elapsed)")
    }

    @Test func `a huge alternation compiles and matches within the program size limit`() throws {
        let words = (0 ..< 2000).map { "word\($0)" }
        let pattern = try Pattern(words.joined(separator: "|"))
        #expect(pattern.firstMatch(in: Array("xx word1999 yy".utf8))?.range == 3 ..< 11)
    }
}
