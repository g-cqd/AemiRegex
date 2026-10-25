import Testing

@testable import AemiRegex

/// A pattern whose every match ends with one byte that nothing else can consume is searched by jumping between occurrences of that byte,
/// and a reverse search from each finds the start. The proof that this finds the leftmost match needs the byte to occur once per match,
/// at its end; each way that can fail disqualifies the pattern.
struct TerminalByteTests {
    static let terminals: [(String, UInt8)] = [
        ("a*b", 0x62), ("ab|cb", 0x62), (#"(\w+)\s*:\s*(\w+)\s*\{"#, 0x7B), ("<[^>]*>", 0x3E), (#"\w+\("#, 0x28),
        (#"#\w+;"#, 0x3B),
        ("x\\n", 0x0A), (#"\w+;\b"#, 0x3B), ("(a+)(b)", 0x62), (#"\d+\.\d*;"#, 0x3B), (#"[^;]*;"#, 0x3B)
    ]

    static let notTerminal: [String] = [
        "x*", "a+", "\"[^\"]*\"", #"foo\b"#, "a(?:b|$)", "é$", "a|b", "ab?", "(?i)ab", "^$", "a.b", "[ab]+b", "(?:ab)+",
        "ab*",
        "a{2,3}", "(?s).*;", ";?", "(?:a;)?", "(?:b;)*"
    ]

    @Test(arguments: terminals)
    func `a pattern ending in a byte that nothing else consumes has it as its terminal byte`(
        source: String, byte: UInt8
    ) throws {
        #expect(try Pattern(source).terminalByte == byte)
    }

    @Test(arguments: notTerminal)
    func `a pattern without such a byte has no terminal byte`(source: String) throws {
        #expect(try Pattern(source).terminalByte == nil, "/\(source)/")
    }

    static let texts = [
        "", "{", "a{", "x: y {", "name : Type {\nfoo: bar{ baz", "é: ü {", "😀 x{ y: z{", "::{{", "ab b ab",
        "<a><b c></d", "foo(",
        "a.b(c)(d", "#x; #yy;", "# ;", "b", "aab ab b", "a: b {c: d {", "ab\nxb\n", "12.5;3.;.;", "ééb éb b",
        "a:b{ ; x : y {"
    ]

    @Test(arguments: terminals.map(\.0))
    func `jumping between terminal bytes finds the matches the Pike VM finds`(source: String) throws {
        let fast = try Pattern(source)
        let reference = try Pattern(source, engine: .pikeOnly)
        for text in Self.texts {
            let bytes = Array(text.utf8)
            #expect(fast.matches(in: bytes) == reference.matches(in: bytes), "/\(source)/ on \(text.debugDescription)")
            #expect(fast.matchCount(in: bytes) == reference.matchCount(in: bytes))
            #expect(fast.isMatch(in: bytes) == reference.isMatch(in: bytes))
            for start in bytes.indices where PikeVM.isBoundary(array: bytes, start) {
                #expect(
                    fast.firstMatch(in: bytes, from: start) == reference.firstMatch(in: bytes, from: start),
                    "/\(source)/ on \(text.debugDescription) from \(start)")
            }
        }
    }

    /// Patterns with a terminal byte and no prefix the prefilter could use instead.
    static let jumping = [#"(\w+)\s*:\s*(\w+)\s*\{"#, #"\w+\("#, #"\w+;\b"#, #"\d+\.\d*;"#, #"[^;]*;"#]

    @Test(arguments: jumping)
    func `a search for such a pattern takes the terminal path, and any other does not`(source: String) throws {
        let pattern = try Pattern(source)
        let before = pattern.searchCounts.terminal
        _ = pattern.matches(in: Array("x: y { a: b {  c(d); 1.5;".utf8))
        #expect(pattern.searchCounts.terminal > before, "/\(source)/ never took the terminal path")
        for other in ["a+", "ab|cb", "x\\n"] {
            let pattern = try Pattern(other)
            _ = pattern.matches(in: Array("aaab xb x\n".utf8))
            #expect(pattern.searchCounts.terminal == 0, "/\(other)/ has a better guide than its terminal byte")
        }
    }

    @Test func `the reverse search never reads before the point the search started from`() throws {
        // `\b` and `^` look before `from`, but the match itself must start at or after it.
        let pattern = try Pattern(#"\w+;"#)
        let text = Array("abc;".utf8)
        #expect(pattern.firstMatch(in: text, from: 1)?.range == 1 ..< 4)
        #expect(pattern.firstMatch(in: text, from: 4) == nil)
        let boundary = try Pattern(#"\bc;"#)
        #expect(
            boundary.firstMatch(in: text, from: 2) == nil,
            "c is not at a word boundary, and the text before `from` shows it")
    }
}
