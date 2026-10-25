import Foundation
import Testing

@testable import AemiRegex

/// RFC 9485 (I-Regexp). Two independent oracles: a recogniser written from the RFC's ABNF decides what is syntactically valid, and Go's
/// `regexp` run on the RFC's own mapping (section 5.4) decides what matches. The unit tests below state the RFC's text directly.
struct IRegexpTests {
    private func bytes(_ s: String) -> [UInt8] { Array(s.utf8) }

    // MARK: Fixtures

    @Test func `the I-Regexp fixtures are present and complete`() {
        #expect(IRegexpFixture.grammar.count == 8000)
        #expect(IRegexpFixture.grammar.filter(\.valid).count > 3000)
        #expect(IRegexpFixture.golden.count > 6000)
    }

    // MARK: The grammar

    @Test func `AemiRegex accepts exactly the patterns the RFC's grammar accepts and an implementation can run`() {
        var disagreements: [String] = []
        for row in IRegexpFixture.grammar {
            let accepted = (try? Pattern(row.p, syntax: .iRegexp)) != nil
            let expected = row.valid && (row.compiles ?? false)
            if accepted != expected, disagreements.count < 12 {
                disagreements.append(
                    "\(row.p.debugDescription): AemiRegex \(accepted ? "accepts" : "rejects"), the RFC grammar \(row.valid ? "accepts" : "rejects")"
                )
            }
        }
        #expect(disagreements.isEmpty, "\(disagreements.joined(separator: "\n"))")
    }

    // MARK: Matching, against Go on the RFC's mapping

    @Test func `whole-string matching agrees with Go on every grammar-valid pattern in the golden corpus`() throws {
        var disagreements: [String] = []
        var compiled: [String: Pattern] = [:]
        for row in IRegexpFixture.golden {
            if row.error == true {
                #expect(throws: PatternError.self, "\(row.p)") { try Pattern(row.p, syntax: .iRegexp) }
                continue
            }
            guard let haystack = row.h, let full = row.full else { continue }
            let pattern = try compiled[row.p] ?? Pattern(row.p, syntax: .iRegexp)
            compiled[row.p] = pattern
            let bytes = Array(haystack.utf8)
            let match = pattern.firstMatch(in: bytes)
            if (match != nil) != full || (match != nil && match?.range != 0 ..< bytes.count), disagreements.count < 12 {
                disagreements.append(
                    "\(row.p.debugDescription) on \(haystack.debugDescription): Go \(full) AemiRegex \(String(describing: match?.range))"
                )
            }
        }
        #expect(disagreements.isEmpty, "\(disagreements.joined(separator: "\n"))")
    }

    @Test func `searching with the same patterns agrees with Go on every match`() throws {
        var disagreements: [String] = []
        var compiled: [String: Pattern] = [:]
        for row in IRegexpFixture.golden where row.error != true {
            guard let haystack = row.h else { continue }
            let pattern = try compiled[row.p] ?? Pattern(row.p, syntax: .iRegexp, matching: .search)
            compiled[row.p] = pattern
            let actual = pattern.matches(in: Array(haystack.utf8)).map { [$0.range.lowerBound, $0.range.upperBound] }
            if actual != (row.all ?? []).map({ Array($0.prefix(2)) }), disagreements.count < 12 {
                disagreements.append(
                    "\(row.p.debugDescription) on \(haystack.debugDescription): Go \(row.all ?? []) AemiRegex \(actual)"
                )
            }
        }
        #expect(disagreements.isEmpty, "\(disagreements.joined(separator: "\n"))")
    }

    // MARK: The RFC's text, stated directly

    @Test func `a dot matches any character except line feed and carriage return`() throws {
        let pattern = try Pattern(".", syntax: .iRegexp)
        for text in ["a", "é", "日", "\u{2028}", "😀", " "] {
            #expect(pattern.firstMatch(in: bytes(text)) != nil, "\(text.debugDescription)")
        }
        for text in ["\n", "\r", "", "ab"] {
            #expect(pattern.firstMatch(in: bytes(text)) == nil, "\(text.debugDescription)")
        }
    }

    @Test func `a caret and a dollar are ordinary characters outside a class`() throws {
        let pattern = try Pattern("^a$", syntax: .iRegexp)
        #expect(pattern.firstMatch(in: bytes("^a$")) != nil)
        #expect(pattern.firstMatch(in: bytes("a")) == nil)
        #expect(
            try Pattern("[^a]", syntax: .iRegexp).firstMatch(in: bytes("b")) != nil,
            "inside a class a leading caret negates")
        #expect(try Pattern("[a^]", syntax: .iRegexp).firstMatch(in: bytes("^")) != nil)
    }

    @Test func `categories follow the Unicode general category, including unassigned code points for C and Cn`() throws
    {
        func matches(_ pattern: String, _ text: String) throws -> Bool {
            try Pattern(pattern, syntax: .iRegexp).firstMatch(in: bytes(text)) != nil
        }
        #expect(try matches(#"\p{Nd}"#, "٣"))
        #expect(try !matches(#"\p{Nd}"#, "a"))
        #expect(try matches(#"\P{L}"#, "1"))
        #expect(try matches(#"[^\p{L}a]"#, "1"))
        #expect(try !matches(#"[^\p{L}a]"#, "b"))
        #expect(try matches(#"\p{Lu}"#, "A") && matches(#"\p{Ll}"#, "a") && matches(#"\p{Lt}"#, "ǅ"))
        #expect(try matches(#"\p{Sc}"#, "€") && matches(#"\p{Zs}"#, " ") && matches(#"\p{Mn}"#, "\u{0301}"))
        // U+0378 has been unassigned since Unicode 1.1; XSD's C and Cn include unassigned code points (Go's do not).
        #expect(try matches(#"\p{Cn}"#, "\u{0378}") && !matches(#"\p{Cn}"#, "a"))
        #expect(try matches(#"\p{C}"#, "\u{0378}") && matches(#"\p{C}"#, "\u{0007}") && !matches(#"\p{C}"#, "a"))
        #expect(try !matches(#"\P{C}"#, "\u{0378}") && matches(#"\P{C}"#, "a"))
    }

    @Test func `the default is whole-string matching, and search is a choice`() throws {
        let whole = try Pattern("b+", syntax: .iRegexp)
        #expect(whole.firstMatch(in: bytes("abbc")) == nil)
        #expect(whole.firstMatch(in: bytes("bb"))?.range == 0 ..< 2)
        #expect(try Pattern("b+", syntax: .iRegexp, matching: .search).firstMatch(in: bytes("abbc"))?.range == 1 ..< 3)
        #expect(
            try Pattern("b+", syntax: .re2).firstMatch(in: bytes("abbc"))?.range == 1 ..< 3,
            "RE2 syntax searches by default")
        #expect(try Pattern("b+", syntax: .re2, matching: .wholeString).firstMatch(in: bytes("abbc")) == nil)
    }

    @Test func `whole-string matching takes the alternative that reaches the end, not the first that matches`() throws {
        let pattern = try Pattern("a|ab", syntax: .iRegexp)
        #expect(pattern.firstMatch(in: bytes("ab"))?.range == 0 ..< 2)
        #expect(pattern.firstMatch(in: bytes("a"))?.range == 0 ..< 1)
        #expect(pattern.firstMatch(in: bytes("abc")) == nil)
    }

    @Test func `an unterminated quote in RE2 syntax cannot swallow the whole-string anchors`() throws {
        let pattern = try Pattern(#"\Qab"#, syntax: .re2, matching: .wholeString)
        #expect(pattern.firstMatch(in: bytes("ab"))?.range == 0 ..< 2)
        #expect(pattern.firstMatch(in: bytes("abc")) == nil)
    }

    /// RFC 9485 section 5.1, Table 1: the substitutes for the multi-character escapes it does not have.
    @Test func `the substitutes the RFC gives for the missing escapes are valid and mean what it says`() throws {
        func accepts(_ pattern: String, _ text: String) throws -> Bool {
            try Pattern(pattern, syntax: .iRegexp).firstMatch(in: bytes(text)) != nil
        }
        #expect(try accepts(#"[^ \t\n\r]"#, "x") && !accepts(#"[^ \t\n\r]"#, " ") && !accepts(#"[^ \t\n\r]"#, "\t"))
        #expect(try accepts(#"[^\t\n\r]"#, " ") && !accepts(#"[^\t\n\r]"#, "\n"))
        #expect(
            try accepts("[0-9]", "7") && !accepts("[0-9]", "٣"), "the substitute for \\d is ASCII digits, not \\p{Nd}")
        for escape in [#"\d"#, #"\s"#, #"\w"#, #"\S"#, #"[\d]"#, #"\p{IsBasicLatin}"#, #"[\u0000-\u007f]"#] {
            #expect(throws: PatternError.self, "\(escape) is not in I-Regexp") { try Pattern(escape, syntax: .iRegexp) }
        }
    }

    // MARK: Errors name the offset in the pattern the caller wrote

    struct Bad: Sendable, CustomTestStringConvertible {
        let source: String
        let error: PatternError
        var testDescription: String { "/\(source)/" }
    }

    static let bad: [Bad] = [
        Bad(source: "(a", error: .syntax(.unmatchedOpenParen, offset: 0)),
        Bad(source: "a)", error: .syntax(.unmatchedCloseParen, offset: 1)),
        Bad(source: "[a", error: .syntax(.unterminatedClass, offset: 0)),
        Bad(source: "a**", error: .syntax(.nestedRepetition, offset: 2)),
        Bad(source: "*a", error: .syntax(.repetitionWithoutOperand, offset: 0)),
        Bad(source: "ab\\d", error: .syntax(.invalidEscape, offset: 2)),
        Bad(source: "x\\p{Cs}", error: .syntax(.unknownClassName, offset: 1)),
        Bad(source: "a{3,2}", error: .syntax(.invalidRepetition, offset: 1)),
        Bad(source: "[z-a]", error: .syntax(.invalidClassRange, offset: 1)),
        // `\n` becomes six characters in the RE2 text, so an error reported from there would carry the wrong offset.
        Bad(source: "\\n[z-a]", error: .syntax(.invalidClassRange, offset: 3)),
        Bad(source: "\\n{3,2}", error: .syntax(.invalidRepetition, offset: 2)),
        Bad(source: "é]", error: .syntax(.invalidCharacter, offset: 2)),
        Bad(source: "a{1001}", error: .limit(.repetitionCount)),
        Bad(source: "[^]", error: .syntax(.invalidClassRange, offset: 0))
    ]

    @Test(arguments: bad)
    func `a pattern outside the grammar names its error and the offset in the original text`(case bad: Bad) {
        #expect(throws: bad.error) { try Pattern(bad.source, syntax: .iRegexp) }
    }

    // MARK: Safety

    @Test func `nesting past the limit is refused without recursing`() {
        let deep = String(repeating: "(", count: 100_000) + "a" + String(repeating: ")", count: 100_000)
        var limits = Pattern.Limits.default
        // The pattern is 200,000 bytes: past the default length limit, so raise it to reach the depth limit.
        limits.maxPatternBytes = 1 << 20
        #expect(throws: PatternError.limit(.nestingDepth)) { try Pattern(deep, syntax: .iRegexp, limits: limits) }
        #expect(throws: PatternError.limit(.patternLength)) { try Pattern(deep, syntax: .iRegexp) }
    }

    @Test func `a repeated category that would exceed the program size is refused, not built`() {
        #expect(throws: PatternError.limit(.programSize)) { try Pattern(#"\p{L}{1000}"#, syntax: .iRegexp) }
    }

    @Test func `a category matches every scalar of its width in UTF-8, and nothing else`() throws {
        let letters = try Pattern(#"\p{L}"#, syntax: .iRegexp)
        for scalar in ["a", "é", "日", "𝒜"] { #expect(letters.firstMatch(in: bytes(scalar)) != nil, "\(scalar)") }
        for malformed: [UInt8] in [[0xC3], [0xE6, 0x97], [0xFF], [0xC0, 0x80], [0xED, 0xA0, 0x80]] {
            #expect(letters.firstMatch(in: malformed) == nil, "\(malformed)")
        }
    }
}
