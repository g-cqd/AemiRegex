import Testing

@testable import AemiRegex

/// `matches`, `isMatch` and the `String` overloads; the oracle suites check the semantics, these check the surface.
struct BacktrackingSearchAPITests {
    @Test(arguments: [BacktrackingPattern.Dialect.ecmaScript, .pcre2])
    func `an empty match may touch the previous match`(dialect: BacktrackingPattern.Dialect) throws {
        let pattern = try BacktrackingPattern("a*", dialect: dialect)
        #expect(try pattern.matches(in: "baac").map(\.range) == [0 ..< 0, 1 ..< 3, 3 ..< 3, 4 ..< 4])
    }

    @Test func `after an empty match ECMAScript moves on and PCRE2 looks for a non-empty match first`() throws {
        let alternatives = "(?:)|a"
        #expect(
            try BacktrackingPattern(alternatives, dialect: .ecmaScript).matches(in: "a").map(\.range) == [
                0 ..< 0, 1 ..< 1
            ])
        #expect(
            try BacktrackingPattern(alternatives, dialect: .pcre2).matches(in: "a").map(\.range) == [
                0 ..< 0, 0 ..< 1, 1 ..< 1
            ])
    }

    @Test func `a String is searched by UTF-8 offset and mapped back with range(in:)`() throws {
        let text = "é😀 b😀😀"
        let pattern = try BacktrackingPattern("(?<=😀)(.)", dialect: .ecmaScript)
        let found = try pattern.matches(in: text)
        let words = found.compactMap { $0.range(in: text) }.map { String(text[$0]) }
        #expect(words == [" ", "😀"])
        let start = text.index(text.startIndex, offsetBy: 3)
        #expect(try pattern.firstMatch(in: text, from: start)?.range == 12 ..< 16)
        #expect(try pattern.isMatch(in: text))
        #expect(try !pattern.isMatch(in: "😀"))
    }

    @Test func `a start offset outside the text gives no match`() throws {
        let pattern = try BacktrackingPattern("", dialect: .pcre2)
        #expect(try pattern.firstMatch(in: [0x61], from: 2) == nil)
        #expect(try pattern.firstMatch(in: [0x61], from: -1) == nil)
        #expect(try pattern.firstMatch(in: [0x61], from: 1)?.range == 1 ..< 1)
    }

    @Test func `the capture count and a group that did not take part are reported`() throws {
        let pattern = try BacktrackingPattern("(a)|(b)", dialect: .pcre2)
        #expect(pattern.captureCount == 2)
        let found = try pattern.firstMatch(in: Array("b".utf8))
        let match = try #require(found)
        #expect(match[group: 1] == nil)
        #expect(match[group: 2] == 0 ..< 1)
    }

    @Test func `a name may repeat in different alternatives in ECMAScript only`() throws {
        let pattern = try BacktrackingPattern("(?<n>a)|(?<n>b)", dialect: .ecmaScript)
        #expect(pattern.groupIndices(named: "n") == [1, 2])
        #expect(pattern.groupIndex(named: "n") == 1)
        #expect(pattern.groupIndex(named: "other") == nil)
        #expect(pattern.groupIndices(named: "other").isEmpty)
        #expect(throws: PatternError.syntax(.duplicateGroupName, offset: 11)) {
            try BacktrackingPattern("(?<n>a)|(?<n>b)", dialect: .pcre2)
        }
        #expect(throws: PatternError.self) { try BacktrackingPattern("(?<n>a)(?<n>b)", dialect: .ecmaScript) }
    }
}
