import Testing

@testable import AemiRegex

/// Differential tests against Go's `regexp` (RE2 semantics). The expected values were produced by Go, not written by hand.
struct GoldenTests {
    @Test func `the golden fixture is present and complete`() {
        #expect(GoldenFixture.validPatterns.count >= 100)
        #expect(GoldenFixture.invalidPatterns.count >= 30)
        #expect(GoldenFixture.rows.count == 2401)
    }

    @Test(arguments: GoldenFixture.validPatterns)
    func `every match and capture agrees with Go`(golden: GoldenPattern) throws {
        let pattern = try Pattern(golden.pattern)
        for (haystack, expected) in golden.cases {
            let actual = pattern.matches(in: Array(haystack.utf8)).map(Self.flatten)
            #expect(actual == expected, "/\(golden.pattern)/ on \(haystack.debugDescription)")
        }
    }

    @Test(arguments: GoldenFixture.invalidPatterns)
    func `a pattern Go rejects is rejected`(source: String) {
        #expect(throws: PatternError.self) { try Pattern(source) }
    }

    /// Go reports a match as `[start0, end0, start1, end1, …]`, with -1 for a group that did not take part.
    private static func flatten(_ match: Match) -> [Int] {
        match.groups.flatMap { [$0?.lowerBound ?? -1, $0?.upperBound ?? -1] }
    }
}
