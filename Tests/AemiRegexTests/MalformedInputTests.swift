import Testing

@testable import AemiRegex

/// Haystacks that are not valid UTF-8, or are arbitrary bytes: the unchecked loops and the C kernel read these, so every engine must
/// agree with the reference (the Pike VM, which indexes with bounds checks) and no match may lie outside the haystack.
struct MalformedInputTests {
    /// Sequences that are invalid, truncated, overlong or encode surrogates, between valid text.
    private static let hostile: [[UInt8]] = [
        [0x80], [0xBF, 0x80], [0xC0, 0x80], [0xC1, 0xBF], [0xC2], [0xE0, 0x80, 0x80], [0xE0, 0x9F, 0xBF],
        [0xED, 0xA0, 0x80],
        [0xED, 0xBF, 0xBF], [0xF0, 0x80, 0x80, 0x80], [0xF4, 0x90, 0x80, 0x80], [0xF5, 0x80, 0x80, 0x80], [0xFF],
        [0xFE, 0xFF],
        [0xE2, 0x82], [0xF0, 0x9F, 0x98], [0xC3, 0xA9], [0xE2, 0x82, 0xAC], [0xF0, 0x9F, 0x98, 0x80], [0x00],
        [0x0A, 0x00, 0x0A]
    ]

    static let haystacks: [[UInt8]] = {
        var rng = SplitMix64(state: 0xBAD_B17E5)
        var result: [[UInt8]] = []
        for _ in 0 ..< 30 {
            result.append(
                (0 ..< Int.random(in: 0 ... 300, using: &rng)).map { _ in UInt8.random(in: 0 ... 255, using: &rng) })
        }
        for _ in 0 ..< 30 {
            var bytes: [UInt8] = []
            for _ in 0 ..< Int.random(in: 0 ... 40, using: &rng) {
                if Bool.random(using: &rng), let piece = hostile.randomElement(using: &rng) {
                    bytes += piece
                } else {
                    bytes += Array("abc é_\nfunc import ".utf8).shuffled(using: &rng)
                        .prefix(Int.random(in: 1 ... 5, using: &rng))
                }
            }
            result.append(bytes)
        }
        return result
    }()

    @Test(arguments: GoldenFixture.validPatterns)
    func `the DFA pipeline agrees with the Pike VM on arbitrary bytes and stays inside the haystack`(
        golden: GoldenPattern
    ) throws {
        let fast = try Pattern(golden.pattern)
        let reference = try Pattern(golden.pattern, engine: .pikeOnly)
        for bytes in Self.haystacks {
            let actual = fast.matches(in: bytes)
            #expect(
                actual == reference.matches(in: bytes),
                "/\(golden.pattern)/ on \(bytes.count) bytes \(bytes.prefix(24))")
            for match in actual {
                #expect(
                    match.range.lowerBound >= 0 && match.range.upperBound <= bytes.count, "match outside the haystack")
            }
        }
    }

    @Test(arguments: [
        "import|struct|enum|class", "(?i)todo|fixme|hack", "func\\s+\\w+", "(a|b|c|d|e|f|g|h|i)x", "\\bé", "[é-ü]+",
        ".é.", "x*|é",
        "(?m)^\\s*$", "é|ü|ö|ä|ë|ï", "\\x{10FFFF}|\\x{80}"
    ])
    func `literal sets, Unicode classes and nullable patterns agree on arbitrary bytes`(source: String) throws {
        let fast = try Pattern(source)
        let reference = try Pattern(source, engine: .pikeOnly)
        for bytes in Self.haystacks {
            #expect(fast.matches(in: bytes) == reference.matches(in: bytes), "/\(source)/ on \(bytes.prefix(24))")
        }
    }

    @Test func `a haystack of every byte value in every rotation never reads out of bounds`() throws {
        let pattern = try Pattern("é|ü|(?i)abc|\\w+")
        let all = (0 ... 255).map { UInt8($0) }
        for shift in 0 ..< 256 {
            let rotated = Array(all[shift...] + all[..<shift])
            for length in [0, 1, 15, 16, 17, 63, 64, 65, 255, 256] {
                _ = pattern.matches(in: Array(rotated.prefix(length)))
            }
        }
    }
}
