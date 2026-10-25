import Testing

@testable import AemiRegex

/// Counting matches and asking whether one exists need only where each match is, so the engine that fills in capture groups does not run.
struct CountingTests {
    private static let patterns = [
        #"(\w+)\s*:\s*(\w+)\s*\{"#, #"(a)(b)?"#, #"(?:(x)|y)+z"#, #"(\d+)-(\d+)"#, #"((a)|(b))*c"#, #"(?m)^(\w+)$"#
    ]
    private static let texts = [
        "name: Type {\n  other : value{ x", "ab a abab", "xyz yz xxz", "10-20 3-4 5-", "abc ac bbc c",
        "one\ntwo\n\nthree", ""
    ]

    @Test(arguments: patterns)
    func `matchCount agrees with the list of matches, and runs no capture engine`(source: String) throws {
        let pattern = try Pattern(source)
        for text in Self.texts {
            let bytes = Array(text.utf8)
            let before = pattern.searchCounts.pike
            let counted = pattern.matchCount(in: bytes)
            #expect(pattern.searchCounts.pike == before, "matchCount ran the Pike VM on \(String(reflecting: text))")
            #expect(counted == pattern.matches(in: bytes).count, "\(source) on \(String(reflecting: text))")
        }
    }

    @Test(arguments: patterns)
    func `isMatch agrees with firstMatch, and runs no capture engine`(source: String) throws {
        let pattern = try Pattern(source)
        for text in Self.texts {
            let bytes = Array(text.utf8)
            let before = pattern.searchCounts.pike
            let answer = pattern.isMatch(in: bytes)
            #expect(pattern.searchCounts.pike == before, "isMatch ran the Pike VM on \(String(reflecting: text))")
            #expect(answer == (pattern.firstMatch(in: bytes) != nil), "\(source) on \(String(reflecting: text))")
        }
    }

    @Test func `a pattern that cannot use the DFA still counts correctly`() throws {
        let pattern = try Pattern(#"(a+)(b*)"#, limits: .default, engine: .pikeOnly)
        #expect(pattern.matchCount(in: Array("aab a b ab".utf8)) == 3)
    }
}
