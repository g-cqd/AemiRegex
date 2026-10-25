import Foundation
import Testing

@testable import AemiRegex

/// Tests for the high-level surface: `wholeMatch`, `prefixMatch`, `replacingMatches`, `replacingFirstMatch`, and `split`.
struct SurfaceTests {
    @Test func `wholeMatch and prefixMatch verify position and span`() throws {
        let pattern = try Pattern(#"[a-z]+"#)
        #expect(pattern.wholeMatch(in: "hello")?.range == 0 ..< 5)
        #expect(pattern.wholeMatch(in: "hello world") == nil)
        #expect(pattern.wholeMatch(in: " hello") == nil)

        #expect(pattern.prefixMatch(in: "hello world")?.range == 0 ..< 5)
        #expect(pattern.prefixMatch(in: " hello") == nil)

        // Substring
        let text = "123 hello world 456"
        // "hello"
        let sub = text[text.index(text.startIndex, offsetBy: 4) ..< text.index(text.startIndex, offsetBy: 9)]
        #expect(pattern.wholeMatch(in: sub) != nil)
    }

    @Test func `replacingMatches replaces with literal string and with transform`() throws {
        let pattern = try Pattern(#"\d+"#)
        let text = "apples: 10, oranges: 25, bananas: 100"
        let replacedAll = pattern.replacingMatches(in: text, with: "NUM")
        #expect(replacedAll == "apples: NUM, oranges: NUM, bananas: NUM")

        let replacedFirst = pattern.replacingFirstMatch(in: text, with: "FIRST")
        #expect(replacedFirst == "apples: FIRST, oranges: 25, bananas: 100")

        let transformed = pattern.replacingMatches(in: text) { match in
            let val = Int(text[match.range(in: text)]) ?? 0
            return "\(val * 2)"
        }
        #expect(transformed == "apples: 20, oranges: 50, bananas: 200")
    }

    @Test func `split splits strings and substrings by regex matches`() throws {
        let pattern = try Pattern(#"\s*,\s*"#)
        let csv = "apple, banana , orange ,grape"
        let parts = pattern.split(in: csv)
        #expect(parts.map(String.init) == ["apple", "banana", "orange", "grape"])

        let maxOne = pattern.split(in: csv, maxSplits: 1)
        #expect(maxOne.map(String.init) == ["apple", "banana , orange ,grape"])

        let withEmpty = try Pattern(",").split(in: ",a,,b,", omittingEmptySubsequences: false)
        #expect(withEmpty.map(String.init) == ["", "a", "", "b", ""])

        let withoutEmpty = try Pattern(",").split(in: ",a,,b,", omittingEmptySubsequences: true)
        #expect(withoutEmpty.map(String.init) == ["a", "b"])
    }

    @Test func `BacktrackingPattern surface matches Pattern behavior`() throws {
        let pattern = try BacktrackingPattern(#"(\w+)\s+\1"#, dialect: .ecmaScript)
        let text = "say hello hello and bye bye now"

        #expect(try pattern.wholeMatch(in: "hello hello") != nil)
        #expect(try pattern.wholeMatch(in: text) == nil)
        #expect(try pattern.prefixMatch(in: "hello hello world") != nil)
        #expect(try pattern.prefixMatch(in: text) == nil)

        let replacedFirst = try pattern.replacingFirstMatch(in: text, with: "DUPLICATE")
        #expect(replacedFirst == "say DUPLICATE and bye bye now")

        let replacedAll = try pattern.replacingMatches(in: text, with: "DUP")
        #expect(replacedAll == "say DUP and DUP now")

        let splitPattern = try BacktrackingPattern(#";\s*"#, dialect: .pcre2)
        let items = try splitPattern.split(in: "one; two;three;  four")
        #expect(items.map(String.init) == ["one", "two", "three", "four"])
    }

    @Test func `pattern properties and descriptions`() throws {
        let p1 = try Pattern("abc")
        #expect(p1.pattern == "abc")
        #expect(p1.syntax == .re2)
        #expect(p1.description == "abc")
        #expect(p1.debugDescription == "Pattern(/abc/, syntax: .re2)")

        let p2 = try Pattern("x+", syntax: .iRegexp)
        #expect(p2.pattern == "x+")
        #expect(p2.syntax == .iRegexp)

        let bp = try BacktrackingPattern(#"(a)\1"#, dialect: .ecmaScript, options: .ignoreCase)
        #expect(bp.pattern == #"(a)\1"#)
        #expect(bp.dialect == .ecmaScript)
        #expect(bp.options == .ignoreCase)
        #expect(bp.description == #"(a)\1"#)
        #expect(bp.debugDescription == #"BacktrackingPattern(/(a)\1/, dialect: .ecmaScript)"#)
    }
}
