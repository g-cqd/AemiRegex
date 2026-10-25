import Foundation
import Testing

@testable import AemiRegex

/// Tests for searching inside a `Substring` and for `Match.checkedRange` on mismatched or short strings.
struct SubstringAPITests {
    @Test func `a Substring slice is searched in place without matching outside its bounds`() throws {
        let base = "prefix: hello 123 world :suffix"
        let start = try #require(base.firstIndex(of: "h"))
        let afterStart = base[start...]
        let colonOffset = try #require(afterStart.firstIndex(of: ":"))
        let sub = base[start ..< colonOffset]  // "hello 123 world "

        let pattern = try Pattern(#"(\w+)\s+(\d+)"#)
        let found = pattern.firstMatch(in: sub)
        let match = try #require(found)
        #expect(match.range(in: sub) == sub.startIndex ..< sub.index(sub.startIndex, offsetBy: 9))
        #expect(String(sub[match.range(in: sub)]) == "hello 123")
        let g1 = try #require(match.range(ofGroup: 1, in: sub))
        #expect(String(sub[g1]) == "hello")
        let g2 = try #require(match.range(ofGroup: 2, in: sub))
        #expect(String(sub[g2]) == "123")

        #expect(pattern.isMatch(in: sub))
        #expect(pattern.matchCount(in: sub) == 1)
        #expect(pattern.matches(in: sub).count == 1)
    }

    @Test func `checkedRange returns nil instead of trapping when given a short or wrong string`() throws {
        let pattern = try Pattern(#"(\w+)"#)
        let text = "a long string with many words"
        let found = pattern.firstMatch(in: text, from: text.index(text.startIndex, offsetBy: 15))
        let match = try #require(found)
        #expect(match.checkedRange(in: text) != nil)

        // Give it a string that is too short
        let short = "tiny"
        #expect(match.checkedRange(in: short) == nil)
        #expect(match.checkedRange(ofGroup: 1, in: short) == nil)

        // Give it a substring that is too short
        let subShort = text.prefix(2)
        #expect(match.checkedRange(in: subShort) == nil)
        #expect(match.checkedRange(ofGroup: 1, in: subShort) == nil)
    }

    @Test func `BacktrackingPattern searches a Substring and respects bounds`() throws {
        let base = "header [item1 and item2] trailer"
        let l = try #require(base.firstIndex(of: "["))
        let r = try #require(base.firstIndex(of: "]"))
        let sub = base[base.index(after: l) ..< r]  // "item1 and item2"

        let pattern = try BacktrackingPattern(#"item(\d)"#, dialect: .ecmaScript)
        let found = try pattern.firstMatch(in: sub)
        let first = try #require(found)
        #expect(String(sub[first.range(in: sub)]) == "item1")
        #expect(try pattern.matches(in: sub).count == 2)
        #expect(try pattern.isMatch(in: sub))

        // Ensure it doesn't match beyond the substring
        let trailer = try BacktrackingPattern(#"trailer"#, dialect: .ecmaScript)
        #expect(try trailer.firstMatch(in: sub) == nil)
    }
}
