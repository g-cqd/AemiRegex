import Testing

@testable import AemiRegex

struct PrefilterTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let pattern: String
        let kind: Prefilter.Kind
        var testDescription: String { "/\(pattern)/" }
    }

    static let cases: [Case] = [
        Case(pattern: "a", kind: .byte(0x61)),
        Case(pattern: "Sendable", kind: .pair(0x53, 0x65)),
        Case(pattern: "func\\s+\\w+", kind: .pair(0x66, 0x75)),
        Case(pattern: "Q[0-9]+Z", kind: .byte(0x51)),
        Case(pattern: "import|struct|enum", kind: .set([0x65, 0x69, 0x73])),
        Case(pattern: "(?i)todo", kind: .set([0x54, 0x74])),
        Case(pattern: "é", kind: .pair(0xC3, 0xA9)),
        Case(pattern: "[0-9]+x", kind: .none),
        Case(pattern: "a*", kind: .none),
        Case(pattern: "^abc", kind: .pair(0x61, 0x62)),
        Case(pattern: #"\bclass\b"#, kind: .pair(0x63, 0x6C)),
        Case(pattern: "(?m)^$", kind: .none),
        Case(pattern: "(a|b|c|d|e|f|g|h|i)x", kind: .none)
    ]

    @Test(arguments: cases)
    func `the prefilter is the most selective scan the pattern allows`(case c: Case) throws {
        #expect(try Pattern(c.pattern).prefilter.kind == c.kind)
    }

    @Test func `a prefilter never skips a position where a match starts`() throws {
        // The golden fixture is the oracle: every start Go reports must be a position the prefilter offers.
        for golden in GoldenFixture.validPatterns {
            let pattern = try Pattern(golden.pattern)
            for (haystack, expected) in golden.cases {
                let bytes = Array(haystack.utf8)
                for match in expected where !match.isEmpty {
                    let start = match[0]
                    let offered = bytes.withUnsafeBufferPointer { pattern.prefilter.next(in: $0, from: start) }
                    #expect(offered == start, "/\(golden.pattern)/ on \(haystack.debugDescription) start \(start)")
                }
            }
        }
    }
}
