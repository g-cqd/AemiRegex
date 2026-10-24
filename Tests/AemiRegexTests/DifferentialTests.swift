import Foundation
import Testing

@testable import AemiRegex

/// Generated patterns over a tiny alphabet, run against `NSRegularExpression` (ICU), which has Perl-style leftmost-first semantics.
/// Quantifiers apply only to atoms that cannot match empty: how a nullable loop body assigns captures is a documented difference
/// between RE2-family engines and ICU, and Go (the independent oracle in `GoldenTests`) covers it.
struct DifferentialTests {
    private struct SplitMix64: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// A generated fragment and whether it can match the empty string.
    private struct Fragment {
        var text: String
        var nullable: Bool
    }

    private static func atom(_ rng: inout SplitMix64, depth: Int) -> Fragment {
        switch Int.random(in: 0 ..< (depth > 0 ? 8 : 5), using: &rng) {
            case 0, 1: return Fragment(text: String("abc".randomElement(using: &rng) ?? "a"), nullable: false)
            case 2: return Fragment(text: ".", nullable: false)
            case 3:
                return Fragment(
                    text: ["[ab]", "[^a]", "[a-c]", "[^bc]", #"\w"#, #"\W"#].randomElement(using: &rng) ?? "[ab]",
                    nullable: false)
            case 4: return Fragment(text: String("abc".randomElement(using: &rng) ?? "a"), nullable: false)
            case 5:
                let inner = alternation(&rng, depth: depth - 1)
                return Fragment(text: "(\(inner.text))", nullable: inner.nullable)
            case 6:
                let inner = alternation(&rng, depth: depth - 1)
                return Fragment(text: "(?:\(inner.text))", nullable: inner.nullable)
            default:
                let inner = alternation(&rng, depth: depth - 1)
                return Fragment(text: "(?i:\(inner.text))", nullable: inner.nullable)
        }
    }

    private static func piece(_ rng: inout SplitMix64, depth: Int) -> Fragment {
        let base = atom(&rng, depth: depth)
        guard !base.nullable, Int.random(in: 0 ..< 3, using: &rng) == 0 else { return base }
        let op = ["*", "+", "?", "*?", "+?", "??", "{2}", "{1,2}", "{0,2}?"].randomElement(using: &rng) ?? "*"
        return Fragment(text: base.text + op, nullable: op.hasPrefix("*") || op.hasPrefix("?") || op.hasPrefix("{0"))
    }

    private static func sequence(_ rng: inout SplitMix64, depth: Int) -> Fragment {
        let parts = (0 ..< Int.random(in: 1 ... 4, using: &rng)).map { _ in piece(&rng, depth: depth) }
        return Fragment(text: parts.map(\.text).joined(), nullable: parts.allSatisfy(\.nullable))
    }

    private static func alternation(_ rng: inout SplitMix64, depth: Int) -> Fragment {
        let branches = (0 ..< Int.random(in: 1 ... 3, using: &rng)).map { _ in sequence(&rng, depth: depth) }
        return Fragment(text: branches.map(\.text).joined(separator: "|"), nullable: branches.contains { $0.nullable })
    }

    private static func haystack(_ rng: inout SplitMix64) -> String {
        String((0 ..< Int.random(in: 0 ... 12, using: &rng)).map { _ in "abcAB \n_".randomElement(using: &rng) ?? "a" })
    }

    @Test func `ten thousand generated pattern and haystack pairs agree with ICU`() throws {
        var rng = SplitMix64(state: 0xA3E1_2026)
        var compared = 0
        var disagreements: [String] = []
        for _ in 0 ..< 2500 {
            let source = Self.alternation(&rng, depth: 2).text
            let ours = try Pattern(source)
            let icu = try NSRegularExpression(pattern: source)
            for _ in 0 ..< 4 {
                let text = Self.haystack(&rng)
                let utf16 = NSRange(location: 0, length: text.utf16.count)
                let expected = icu.firstMatch(in: text, range: utf16)
                    .map { m in
                        (0 ... icu.numberOfCaptureGroups)
                            .map { i -> Range<Int>? in
                                let r = m.range(at: i)
                                return r.location == NSNotFound ? nil : r.location ..< r.location + r.length
                            }
                    }
                let actual = ours.firstMatch(in: Array(text.utf8))?.groups
                compared += 1
                if expected != actual, disagreements.count < 10 {
                    disagreements.append(
                        "/\(source)/ on \(text.debugDescription): ICU \(String(describing: expected)) ours \(String(describing: actual))"
                    )
                }
            }
        }
        #expect(compared == 10_000)
        #expect(disagreements.isEmpty, "\(disagreements.joined(separator: "\n"))")
    }
}
