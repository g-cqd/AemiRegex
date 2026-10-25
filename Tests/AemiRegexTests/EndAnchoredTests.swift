import Testing

@testable import AemiRegex

/// A pattern whose every match must end at the end of the text is searched backwards from the end: the reverse DFA finds the leftmost
/// start and only reads what the match covers, instead of a forward scan of the whole haystack. The rule for "every match" is
/// conservative: one path to a match that avoids the end-of-text assertion disqualifies the pattern.
struct EndAnchoredTests {
    @Test(arguments: [
        ("[ \\t]*$", true), ("abc$", true), ("a$|b$", true), ("(a$)", true), ("a\\z", true), ("$", true), ("^$", true),
        ("\\bfoo\\b$", true),
        ("(?:ab|cd)+$", true), ("a$|b", false), ("a$|", false), ("(?m)a$", false), ("a", false), ("x(?:y$)?", false),
        ("a*", false),
        ("\\Aabc", false), ("a(?:$|b)", false), ("(a|b$)c", false)
    ])
    func `a pattern is end-anchored only when every path to a match crosses the end-of-text assertion`(
        source: String, anchored: Bool
    ) throws {
        #expect(try Pattern(source).endAnchored == anchored)
    }

    @Test(arguments: [
        ("[ \\t]*$", "foo   "), ("[ \\t]*$", "foo"), ("[ \\t]*$", ""), ("[ \\t]*$", "é  "), ("abc$", "xabc"),
        ("abc$", "abcx"),
        ("a$|b$", "xb"), ("(a+)$", "baaa"), ("(a+)(b*)$", "aab"), ("\\bfoo\\b$", "a foo"), ("$", "héllo"),
        ("a$", "a\n"),
        ("(?:ab|cd)+$", "xabcd"), ("é$", "caf\u{E9}"), (".*$", "ab\ncd"), ("x*$", "xxx")
    ])
    func `searching backwards from the end gives the matches the forward engines give`(source: String, text: String)
        throws
    {
        let fast = try Pattern(source)
        let reference = try Pattern(source, engine: .pikeOnly)
        let bytes = Array(text.utf8)
        #expect(fast.matches(in: bytes) == reference.matches(in: bytes), "/\(source)/ on \(text.debugDescription)")
        #expect(fast.firstMatch(in: bytes) == reference.firstMatch(in: bytes))
        for from in 0 ... bytes.count {
            #expect(
                fast.firstMatch(in: bytes, from: from) == reference.firstMatch(in: bytes, from: from), "from \(from)")
        }
    }

    @Test func `an end-anchored search is answered by the backward scan alone`() throws {
        let pattern = try Pattern("[ \\t]*$")
        _ = pattern.firstMatch(in: Array("foo   ".utf8))
        #expect(pattern.searchCounts == SearchCounts(literal: 0, dfa: 0, pike: 0, endAnchored: 1))
        let other = try Pattern("foo")
        _ = other.firstMatch(in: Array("foo".utf8))
        #expect(other.searchCounts.endAnchored == 0)
    }

    @Test func `the backward scan reads only what the match covers, however long the haystack`() throws {
        let pattern = try Pattern("[ \\t]*$")
        let text = [UInt8](repeating: 0x78, count: 2_000_000) + [UInt8](repeating: 0x20, count: 5)
        #expect(pattern.firstMatch(in: text)?.range == 2_000_000 ..< 2_000_005)
        let none = try Pattern("abc$")
        #expect(none.firstMatch(in: [UInt8](repeating: 0x78, count: 2_000_000)) == nil)
    }

    @Test func `captures are filled in for an end-anchored match`() throws {
        let match = try #require(try Pattern("(a+)(b*)$").firstMatch(in: Array("xaab".utf8)))
        #expect(match.range == 1 ..< 4)
        #expect(match[group: 1] == 1 ..< 3)
        #expect(match[group: 2] == 3 ..< 4)
    }
}
