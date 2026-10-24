import Testing

@testable import AemiRegex

/// The DFA pipeline and the Pike VM must give identical matches: the Pike VM is the reference the DFA is checked against.
struct EngineAgreementTests {
    @Test(arguments: GoldenFixture.validPatterns)
    func `the automatic pipeline and the Pike VM agree on every golden case`(golden: GoldenPattern) throws {
        let fast = try Pattern(golden.pattern)
        let reference = try Pattern(golden.pattern, engine: .pikeOnly)
        for (haystack, _) in golden.cases {
            let bytes = Array(haystack.utf8)
            #expect(
                fast.matches(in: bytes) == reference.matches(in: bytes),
                "/\(golden.pattern)/ on \(haystack.debugDescription)")
        }
    }

    @Test(arguments: [
        "abc", "a|b", "(a)(b)", "^a", "a$", #"\bfoo\b"#, "(?m)^import \\w+$", "a*", "", "x?", "^$", #"\b"#, "(?m)^",
        "(?m)$"
    ])
    func `every pattern runs through the DFA pipeline, empty-matching ones included, unless the engine is forced`(
        source: String
    ) throws {
        #expect(try Pattern(source).usesDFA)
        #expect(try !Pattern(source, engine: .pikeOnly).usesDFA)
    }

    struct EmptyCase: Sendable, CustomTestStringConvertible {
        let pattern: String
        let haystack: String
        var testDescription: String { "/\(pattern)/ on \(haystack.debugDescription)" }
    }

    static let emptyCases: [EmptyCase] = [
        EmptyCase(pattern: "x*", haystack: "héx"),
        EmptyCase(pattern: "", haystack: "日本語"),
        EmptyCase(pattern: #"\b"#, haystack: "é a é"),
        EmptyCase(pattern: "(?m)$", haystack: "é\né\n"),
        EmptyCase(pattern: "a*|é", haystack: "ééa"),
        EmptyCase(pattern: "(?:)", haystack: "𝄞x")
    ]

    @Test(arguments: emptyCases)
    func `an empty match is never reported inside a multi-byte scalar by the DFA pipeline`(case c: EmptyCase) throws {
        let bytes = Array(c.haystack.utf8)
        let fast = try Pattern(c.pattern).matches(in: bytes)
        let reference = try Pattern(c.pattern, engine: .pikeOnly).matches(in: bytes)
        #expect(fast == reference)
        for match in fast where match.range.isEmpty {
            #expect(PikeVM.isBoundary(bytes, match.range.lowerBound), "empty match at \(match.range.lowerBound)")
        }
    }

    struct ContextCase: Sendable, CustomTestStringConvertible {
        let pattern: String
        let haystack: String
        let from: Int
        var testDescription: String { "/\(pattern)/ on \(haystack.debugDescription) from \(from)" }
    }

    static let contextCases: [ContextCase] = [
        ContextCase(pattern: #"\bcd"#, haystack: "ab cd", from: 3),
        ContextCase(pattern: #"\bb"#, haystack: "ab cd", from: 1),
        ContextCase(pattern: "^b", haystack: "ab", from: 1),
        ContextCase(pattern: "(?m)^b", haystack: "a\nb", from: 2),
        ContextCase(pattern: "(?m)a$", haystack: "a\nb", from: 0),
        ContextCase(pattern: "a$", haystack: "a\n", from: 0),
        ContextCase(pattern: #"o\b"#, haystack: "foo_bar foo", from: 0),
        ContextCase(pattern: #"\Boo"#, haystack: "foo oo", from: 0),
        ContextCase(pattern: "c$", haystack: "abc", from: 2),
        ContextCase(pattern: #"\bé"#, haystack: "aé é", from: 0)
    ]

    @Test(arguments: contextCases)
    func `an assertion sees the bytes before the start offset and the byte after the match, as the Pike VM does`(
        case c: ContextCase
    ) throws {
        let bytes = Array(c.haystack.utf8)
        let fast = try Pattern(c.pattern)
        let reference = try Pattern(c.pattern, engine: .pikeOnly)
        #expect(fast.usesDFA)
        #expect(fast.firstMatch(in: bytes, from: c.from) == reference.firstMatch(in: bytes, from: c.from))
    }

    @Test func `a pattern whose DFA outgrows the cache gives up cleanly and still answers correctly`() throws {
        // The pattern cannot match until the final `c`, so unanchored threads stay alive and the DFA keeps adding states.
        let source = "a(a|b){12}c"
        var tiny = Pattern.Limits.default
        tiny.maxDFACacheBytes = 2_048
        let small = try Pattern(source, limits: tiny)
        let roomy = try Pattern(source)
        let reference = try Pattern(source, engine: .pikeOnly)
        let text = Array("abbabababbbabaabbababbabbbaaabbbabababaabbabbbabaabbaabbaabbac".utf8)
        #expect(small.forwardOutcome(in: text) == .gaveUp)
        #expect(roomy.forwardOutcome(in: text) != .gaveUp)
        #expect(small.matches(in: text) == reference.matches(in: text))
        #expect(roomy.matches(in: text) == reference.matches(in: text))
    }

    @Test func `concurrent searches on one pattern share its caches without a race or a wrong answer`() async throws {
        let pattern = try Pattern("(\\w+)@(\\w+)\\.com")
        let text = Array("mail bob@example.com and amy@test.com now".utf8)
        let expected = pattern.matches(in: text)
        let results = await withTaskGroup(of: [Match].self) { group in
            for _ in 0 ..< 64 {
                group.addTask {
                    var last: [Match] = []
                    for _ in 0 ..< 50 { last = pattern.matches(in: text) }
                    return last
                }
            }
            var collected: [[Match]] = []
            for await result in group { collected.append(result) }
            return collected
        }
        #expect(results.allSatisfy { $0 == expected })
    }
}
