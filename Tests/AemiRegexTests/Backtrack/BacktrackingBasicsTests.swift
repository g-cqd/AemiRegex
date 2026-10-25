import Testing

@testable import AemiRegex

/// The constructs only the backtracker can run, with expectations checked against `node` (ECMAScript) and `libpcre2` (PCRE2).
struct BacktrackingBasicsTests {
    private func find(
        _ pattern: String, _ text: String, _ dialect: BacktrackingPattern.Dialect = .pcre2
    ) throws -> [Range<Int>?]? {
        let compiled = try BacktrackingPattern(pattern, dialect: dialect)
        return try compiled.firstMatch(in: Array(text.utf8))?.groups
    }

    @Test(arguments: [BacktrackingPattern.Dialect.ecmaScript, .pcre2])
    func `a backreference repeats what its group matched`(dialect: BacktrackingPattern.Dialect) throws {
        #expect(try find(#"(a+)b\1"#, "aabaa", dialect) == [0 ..< 5, 0 ..< 2])
        #expect(try find(#"(a+)b\1"#, "aaba", dialect) == [1 ..< 4, 1 ..< 2])
        #expect(try find(#"(\w)\1"#, "abccd", dialect) == [2 ..< 4, 2 ..< 3])
    }

    @Test(arguments: [BacktrackingPattern.Dialect.ecmaScript, .pcre2])
    func `lookahead looks without consuming`(dialect: BacktrackingPattern.Dialect) throws {
        #expect(try find("foo(?=bar)", "foobar", dialect) == [0 ..< 3])
        #expect(try find("foo(?!bar)", "foobar foobaz", dialect) == [7 ..< 10])
        #expect(try find("(?=(a+))a*b", "aaab", dialect) == [0 ..< 4, 0 ..< 3])
    }

    @Test(arguments: [BacktrackingPattern.Dialect.ecmaScript, .pcre2])
    func `lookbehind reads the text before the position`(dialect: BacktrackingPattern.Dialect) throws {
        #expect(try find(#"(?<=\$)\d+"#, "cost $45", dialect) == [6 ..< 8])
        #expect(try find(#"(?<!\$)\b\d+"#, "$45 or 67", dialect) == [7 ..< 9])
        #expect(try find("(?<=é)x", "éx", dialect) == [2 ..< 3])
    }

    @Test func `an atomic group and a possessive quantifier do not give back`() throws {
        #expect(try find("(?>a+)ab", "aaab") == nil)
        #expect(try find("a++ab", "aaab") == nil)
        #expect(try find("(?>a+)b", "aaab") == [0 ..< 4])
    }

    @Test(arguments: [BacktrackingPattern.Dialect.ecmaScript, .pcre2])
    func `a lazy quantifier takes as little as it can`(dialect: BacktrackingPattern.Dialect) throws {
        #expect(try find("<.+?>", "<a><b>", dialect) == [0 ..< 3])
        #expect(try find("<.+>", "<a><b>", dialect) == [0 ..< 6])
    }

    @Test func `a pattern that explodes ends in budgetExceeded, not a hang`() throws {
        let pattern = try BacktrackingPattern("(a+)+b", dialect: .pcre2)
        let text = Array(String(repeating: "a", count: 60).utf8)
        #expect(throws: BacktrackError.budgetExceeded(.steps)) { try pattern.firstMatch(in: text) }
    }

    @Test func `a long input ends in budgetExceeded on the stack, not in a crash`() throws {
        let budget = BacktrackingPattern.Budget(maxSteps: 100_000_000, maxStackEntries: 10_000)
        let pattern = try BacktrackingPattern("(?:a|b)*c", dialect: .pcre2, budget: budget)
        let text = Array(String(repeating: "ab", count: 50_000).utf8)
        #expect(throws: BacktrackError.budgetExceeded(.stack)) { try pattern.firstMatch(in: text) }
    }
}
