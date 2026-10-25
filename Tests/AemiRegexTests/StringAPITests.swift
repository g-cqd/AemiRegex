import Foundation
import Testing

@testable import AemiRegex

/// The `String` entry points search a string's UTF-8 in place and return ranges in `String.Index`. They must give exactly what the byte
/// entry points give, mapped back to the string, for text with multi-byte characters, empty text, and strings that do not store UTF-8
/// contiguously.
struct StringAPITests {
    private static let texts = [
        "", "a", "héllo wörld", "日本語 abc 日本", "emoji 😀 x 😀", "a\nb\r\nc", "e\u{301}x", "ΑαΩω", "tab\tsep",
        "xxxxxxxxxxxxxxxxxxxxxxxxxx 😀y"
    ]
    private static let sources = [
        "\\w+", "é|ö|日", "(?i)α", ".", "x*", "(\\w)(\\w)", "\\bw", "[^a]$", "日.", "😀", "\\p{Greek}+", "$"
    ]

    private static func slice(_ text: String, _ range: Range<Int>) -> String {
        String(decoding: Array(text.utf8)[range], as: UTF8.self)
    }

    @Test(arguments: sources)
    func `every match in a string is the match in its bytes, mapped back to the string`(source: String) throws {
        let pattern = try Pattern(source)
        for text in Self.texts {
            let viaBytes = pattern.matches(in: Array(text.utf8))
            let viaString = pattern.matches(in: text)
            #expect(viaString == viaBytes, "/\(source)/ on \(text.debugDescription)")
            for match in viaString {
                #expect(
                    String(text[match.range(in: text)]) == Self.slice(text, match.range),
                    "/\(source)/ on \(text.debugDescription)")
                for group in 1 ..< match.groups.count {
                    let expected = match[group: group].map { Self.slice(text, $0) }
                    #expect(match.range(ofGroup: group, in: text).map { String(text[$0]) } == expected)
                }
            }
        }
    }

    @Test func `a search can start at a string index`() throws {
        let text = "héllo wörld"
        let pattern = try Pattern("\\pL+")
        let world = try #require(text.firstIndex(of: "w"))
        let match = try #require(pattern.firstMatch(in: text, from: world))
        #expect(String(text[match.range(in: text)]) == "wörld")
        #expect(pattern.firstMatch(in: text, from: text.endIndex) == nil)
        #expect(try Pattern("x*").firstMatch(in: text, from: text.endIndex)?.range == 13 ..< 13)
    }

    @Test func `counting and iterating give the matches without building them all`() throws {
        let pattern = try Pattern("\\w+")
        let text = "one two  three four"
        #expect(pattern.matchCount(in: text) == 4)
        #expect(pattern.matchCount(in: Array(text.utf8)) == 4)
        var seen: [String] = []
        pattern.forEachMatch(in: text) { match in
            seen.append(String(text[match.range(in: text)]))
            return true
        }
        #expect(seen == ["one", "two", "three", "four"])
        var first: [String] = []
        pattern.forEachMatch(in: text) { match in
            first.append(String(text[match.range(in: text)]))
            return first.count < 2
        }
        #expect(first == ["one", "two"], "returning false stops the iteration")
    }

    @Test func `isMatch says whether there is a match, and for a whole-string pattern whether the string is one`()
        throws
    {
        #expect(try Pattern("b+").isMatch(in: "abbc"))
        #expect(try !Pattern("z").isMatch(in: "abbc"))
        let whole = try Pattern("b+", syntax: .iRegexp)
        #expect(!whole.isMatch(in: "abbc") && whole.isMatch(in: "bb"))
        #expect(try Pattern("").isMatch(in: ""))
    }

    #if canImport(Darwin)
        @Test func `a bridged string that is not stored as contiguous UTF-8 gives the same answers`() throws {
            let native = "héllo wörld 日本語"
            let bridged = NSString(string: native) as String
            let pattern = try Pattern("\\pL+")
            let expected = pattern.matches(in: native).map(\.range)
            #expect(pattern.matches(in: bridged).map(\.range) == expected)
            let match = try #require(pattern.firstMatch(in: bridged))
            #expect(String(bridged[match.range(in: bridged)]) == "héllo")
        }
    #endif

    @Test func `a long string is searched in place without a copy of the pattern's answer changing`() throws {
        let text = String(repeating: "word ", count: 20_000) + "needle"
        let pattern = try Pattern("needle")
        let match = try #require(pattern.firstMatch(in: text))
        #expect(String(text[match.range(in: text)]) == "needle")
        #expect(match.range == 100_000 ..< 100_006)
        #expect(pattern.matchCount(in: text) == 1)
    }
}
