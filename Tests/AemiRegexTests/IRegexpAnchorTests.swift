import Testing

@testable import AemiRegex

/// `Syntax.iRegexpWithAnchors`: JSONPath's reading, where `^` and `$` outside a class are anchors (the compliance suite's `match()` tests).
struct IRegexpAnchorTests {
    private func found(_ pattern: String, _ text: String, matching: Pattern.Matching) throws -> Bool {
        try Pattern(pattern, syntax: .iRegexpWithAnchors, matching: matching).isMatch(in: Array(text.utf8))
    }

    @Test func `a caret and a dollar anchor, in a whole-string match and in a search`() throws {
        #expect(try found("^ab.*", "abc", matching: .wholeString))
        #expect(try found(".*bc$", "abc", matching: .wholeString))
        #expect(try !found("^ab.*", "xab", matching: .wholeString))
        #expect(try found("^ab", "abc", matching: .search))
        #expect(try !found("^ab", "xabc", matching: .search))
        #expect(try found("bc$", "abc", matching: .search))
        #expect(try !found("bc$", "abcx", matching: .search))
    }

    @Test func `an anchor in the middle can never match, and a caret has its escape and a dollar its class`() throws {
        #expect(try !found("a^b", "a^b", matching: .wholeString))
        #expect(try !found("a$b", "a$b", matching: .wholeString))
        #expect(try found(#"a\^b"#, "a^b", matching: .wholeString))
        #expect(try found("a[$]b", "a$b", matching: .wholeString))
    }

    @Test func `a caret or dollar in a class is still a character, and an anchor cannot be repeated`() throws {
        #expect(try found("[a^$]+", "a^$", matching: .wholeString))
        #expect(try !found("[^a]", "a", matching: .wholeString))
        #expect(throws: PatternError.self) { try Pattern("^*", syntax: .iRegexpWithAnchors) }
        #expect(throws: PatternError.self) { try Pattern("$+", syntax: .iRegexpWithAnchors) }
    }

    @Test func `the strict syntax still reads them as characters`() throws {
        let strict = try Pattern("^x$", syntax: .iRegexp)
        #expect(strict.isMatch(in: Array("^x$".utf8)))
        #expect(!strict.isMatch(in: Array("x".utf8)))
    }

    @Test func `every other rule is the strict one`() {
        for source in [#"\d"#, "(?:a)", "a**", "[z-a]", #"\p{Foo}"#] {
            #expect(throws: PatternError.self) { try Pattern(source, syntax: .iRegexpWithAnchors) }
        }
    }
}
