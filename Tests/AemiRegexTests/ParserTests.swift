import Testing

@testable import AemiRegex

struct ParserTests {
    struct Bad: Sendable, CustomTestStringConvertible {
        let source: String
        let error: PatternError
        var testDescription: String { "/\(source)/" }
    }

    private static let bad: [Bad] = [
        Bad(source: "(a", error: .syntax(.unmatchedOpenParen, offset: 0)),
        Bad(source: "a)", error: .syntax(.unmatchedCloseParen, offset: 1)),
        Bad(source: "[a", error: .syntax(.unterminatedClass, offset: 0)),
        Bad(source: "[z-a]", error: .syntax(.invalidClassRange, offset: 1)),
        Bad(source: "*a", error: .syntax(.repetitionWithoutOperand, offset: 0)),
        Bad(source: "a**", error: .syntax(.nestedRepetition, offset: 2)),
        Bad(source: "a{2,1}", error: .syntax(.invalidRepetition, offset: 1)),
        Bad(source: "a\\", error: .syntax(.unexpectedEnd, offset: 1)),
        Bad(source: "\\8", error: .syntax(.invalidEscape, offset: 0)),
        Bad(source: "(?z)", error: .syntax(.invalidFlag, offset: 2)),
        Bad(source: "(?P<n>a)(?P<n>b)", error: .syntax(.duplicateGroupName, offset: 12)),
        Bad(source: "(?P<1a>x)", error: .syntax(.invalidGroupName, offset: 4)),
        Bad(source: "(?=a)", error: .syntax(.unsupported, offset: 1)),
        Bad(source: "(a)\\1", error: .syntax(.unsupported, offset: 3)),
        Bad(source: "[[:nope:]]", error: .syntax(.unknownClassName, offset: 1)),
        Bad(source: "\\x{110000}", error: .syntax(.invalidScalar, offset: 0)),
        Bad(source: "a{1001}", error: .limit(.repetitionCount))
    ]

    @Test(arguments: bad)
    func `a malformed pattern names its error and offset`(case bad: Bad) {
        #expect(throws: bad.error) { try Pattern(bad.source) }
    }

    @Test func `a pattern longer than the limit is rejected before it is parsed`() {
        let limits = Pattern.Limits(
            maxPatternBytes: 8, maxNestingDepth: 250, maxProgramSize: 100_000, maxRepetition: 1000)
        #expect(throws: PatternError.limit(.patternLength)) { try Pattern("abcdefghi", limits: limits) }
        #expect(throws: Never.self) { try Pattern("abcdefgh", limits: limits) }
    }

    @Test func `nesting deeper than the limit is rejected without recursing`() {
        let deep = String(repeating: "(", count: 100_000) + "a" + String(repeating: ")", count: 100_000)
        let limits = Pattern.Limits(
            maxPatternBytes: 1 << 20, maxNestingDepth: 250, maxProgramSize: 1 << 20, maxRepetition: 1000)
        #expect(throws: PatternError.limit(.nestingDepth)) { try Pattern(deep, limits: limits) }
    }

    @Test func `a repetition of a repetition that would exceed the program size is rejected`() {
        #expect(throws: PatternError.limit(.programSize)) { try Pattern("((a{1000}){1000}){1000}") }
    }

    @Test func `capture groups are counted and named in order`() throws {
        let pattern = try Pattern("(a)(?:b)(?P<year>c)(?<month>d)")
        #expect(pattern.captureCount == 3)
        #expect(pattern.groupIndex(named: "year") == 2)
        #expect(pattern.groupIndex(named: "month") == 3)
        #expect(pattern.groupIndex(named: "day") == nil)
    }
}
