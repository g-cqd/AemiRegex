import Testing

@testable import AemiRegex

/// `wholeMatch(in:)` is the highest-priority match that spans the whole text, as Swift `Regex.wholeMatch` and RE2's `FullMatch` define it,
/// not the leftmost-first match kept when it happens to span (roadmap 0015).
struct WholeMatchTests {
    @Test func `a preferred branch that is a prefix of another does not hide the whole match`() throws {
        #expect(try Pattern("a|ab").wholeMatch(in: "ab")?.range == 0 ..< 2)
        #expect(try Pattern("(?:x|xy)+").wholeMatch(in: "xyxxy")?.range == 0 ..< 5)
        #expect(try Pattern("a|ab").wholeMatch(in: "abc") == nil)
        #expect(try Pattern("a|ab").wholeMatch(in: "a")?.range == 0 ..< 1)
    }

    @Test func `the captures are those of the whole match Swift Regex picks`() throws {
        let source = "(a|ab)(c|bcd)(d*)"
        let text = "abcd"
        let ours = try #require(try Pattern(source).wholeMatch(in: text))
        let theirs = try #require(try Regex(source).wholeMatch(in: text))
        let utf8 = text.utf8
        let expected = (0 ..< theirs.output.count)
            .map { group in
                theirs.output[group].range
                    .map {
                        utf8.distance(from: utf8.startIndex, to: $0.lowerBound)
                            ..< utf8.distance(from: utf8.startIndex, to: $0.upperBound)
                    }
            }
        #expect(ours.groups == expected)
    }

    @Test func `a substring is matched whole, relative to its own start`() throws {
        let text = "xx ab yy"
        let sub = text.dropFirst(3).prefix(2)
        #expect(try Pattern("a|ab").wholeMatch(in: sub)?.range == 0 ..< 2)
    }

    @Test func `copies of a pattern share one whole-string program and agree`() async throws {
        let pattern = try Pattern("(?:foo|foobar)(?:baz)?")
        let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for index in 0 ..< 64 {
                let copy = pattern
                group.addTask { copy.wholeMatch(in: index.isMultiple(of: 2) ? "foobar" : "foobarbaz") != nil }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        #expect(results.allSatisfy { $0 })
    }

    @Test func `a pattern compiled whole-string or in I-Regexp is unchanged`() throws {
        #expect(try Pattern("a|ab", syntax: .re2, matching: .wholeString).wholeMatch(in: "ab")?.range == 0 ..< 2)
        #expect(try Pattern("a|ab", syntax: .iRegexp).wholeMatch(in: "ab")?.range == 0 ..< 2)
        #expect(try Pattern("a|ab", syntax: .iRegexp).wholeMatch(in: "abab") == nil)
    }

    @Test(arguments: [BacktrackingPattern.Dialect.ecmaScript, .pcre2])
    func `the backtracker backtracks into the next branch to reach the end`(dialect: BacktrackingPattern.Dialect) throws
    {
        #expect(try BacktrackingPattern("a|ab", dialect: dialect).wholeMatch(in: "ab")?.range == 0 ..< 2)
        let pattern = try BacktrackingPattern("(a|ab)(c|bcd)(d*)", dialect: dialect)
        let match = try #require(try pattern.wholeMatch(in: "abcd"))
        #expect(match.range == 0 ..< 4)
        #expect(match.groups == [0 ..< 4, 0 ..< 1, 1 ..< 4, 4 ..< 4])
        #expect(try BacktrackingPattern("(\\w+) \\1", dialect: dialect).wholeMatch(in: "ab ab")?.range == 0 ..< 5)
        #expect(try BacktrackingPattern("a|ab", dialect: dialect).wholeMatch(in: "abc") == nil)
    }

    @Test func `a failing whole match on the backtracker tries one start, not every one`() throws {
        // From every start `a+b` runs to the end and back, O(n²) steps in all; anchored at the start it is O(n).
        let pattern = try BacktrackingPattern(
            "a+b", dialect: .ecmaScript, budget: .init(maxSteps: 50_000, maxStackEntries: 1 << 16))
        let text = String(repeating: "a", count: 2_000)
        #expect(try pattern.wholeMatch(in: text) == nil)
        #expect(try pattern.prefixMatch(in: text + "b")?.range == 0 ..< 2_001)
    }
}
