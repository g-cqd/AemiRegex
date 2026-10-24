import Testing

@testable import AemiRegex

struct SemanticsTests {
    private func bytes(_ s: String) -> [UInt8] { Array(s.utf8) }

    @Test func `a match is reported in UTF-8 byte offsets`() throws {
        let match = try #require(try Pattern("wörld").firstMatch(in: bytes("héllo wörld")))
        #expect(match.range == 7 ..< 13)
    }

    @Test func `a dot matches a whole multi-byte scalar and never half of one`() throws {
        let all = try Pattern(".").matches(in: bytes("é日"))
        #expect(all.map(\.range) == [0 ..< 2, 2 ..< 5])
    }

    @Test func `bytes that are not valid UTF-8 are skipped, not matched by a scalar class`() throws {
        let haystack: [UInt8] = [0xFF, 0x61, 0xC3, 0x62]  // invalid, a, truncated é, b
        #expect(try Pattern(".").matches(in: haystack).map(\.range) == [1 ..< 2, 3 ..< 4])
    }

    @Test func `matching starts at the given offset but assertions still see the bytes before it`() throws {
        let haystack = bytes("ab cd")
        #expect(try Pattern(#"\bcd"#).firstMatch(in: haystack, from: 3)?.range == 3 ..< 5)
        #expect(try Pattern(#"\bb"#).firstMatch(in: haystack, from: 1) == nil)
        #expect(try Pattern("^b").firstMatch(in: haystack, from: 1) == nil)
    }

    @Test func `an alternation prefers the earlier branch, not the longer one`() throws {
        #expect(try Pattern("a|ab").firstMatch(in: bytes("ab"))?.range == 0 ..< 1)
        #expect(try Pattern("ab|a").firstMatch(in: bytes("ab"))?.range == 0 ..< 2)
    }

    @Test func `a group that did not take part is nil and one that repeated keeps its last text`() throws {
        let first = try #require(try Pattern("(a)|(b)").firstMatch(in: bytes("b")))
        #expect(first.groups == [0 ..< 1, nil, 0 ..< 1])
        let last = try #require(try Pattern("(a|b)+").firstMatch(in: bytes("abba")))
        #expect(last.groups == [0 ..< 4, 3 ..< 4])
    }

    @Test func `an empty match that touches the previous match is skipped`() throws {
        #expect(try Pattern("a*").matches(in: bytes("baaac")).map(\.range) == [0 ..< 0, 1 ..< 4, 5 ..< 5])
    }

    @Test func `an empty match is never reported inside a multi-byte scalar`() throws {
        #expect(try Pattern("x*").matches(in: bytes("héx")).map(\.range) == [0 ..< 0, 1 ..< 1, 3 ..< 4])
    }

    @Test func `an empty haystack and an empty pattern both work`() throws {
        #expect(try Pattern("").matches(in: []).map(\.range) == [0 ..< 0])
        #expect(try Pattern("a").matches(in: []).isEmpty)
    }

    @Test func `a start offset past the end finds nothing instead of trapping`() throws {
        #expect(try Pattern("a*").firstMatch(in: bytes("a"), from: 2) == nil)
        #expect(try Pattern("a*").firstMatch(in: bytes("a"), from: -1) == nil)
        #expect(try Pattern("a*").firstMatch(in: bytes("a"), from: 1)?.range == 1 ..< 1)
    }

    @Test func `the README example gives the ranges it states`() throws {
        let pattern = try Pattern(#"(?P<name>\w+)@(\w+)\.com"#)
        let match = try #require(pattern.firstMatch(in: bytes("mail bob@example.com now")))
        #expect(match.range == 5 ..< 20)
        #expect(match.groups[try #require(pattern.groupIndex(named: "name"))] == 5 ..< 8)
    }
}
