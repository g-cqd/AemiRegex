import Foundation
import Testing

@testable import AemiRegex

/// Generated patterns over a tiny alphabet, run against `NSRegularExpression` (ICU), which has Perl-style leftmost-first semantics.
/// No assertions are generated: ICU and RE2 disagree on `\b`, `\B`, `$` and multiline `^` in some cases (on three generated cases
/// Go sided with AemiRegex), so assertions are checked against Go in `GeneratedGoldenTests`. Quantifiers apply only to atoms that cannot match empty: how a nullable loop body assigns captures is a documented difference
/// between RE2-family engines and ICU, and Go (the independent oracle in `GoldenTests`) covers it.
struct DifferentialTests {
    /// A generated fragment and whether it can match the empty string.
    private struct Fragment {
        var text: String
        var nullable: Bool
    }

    /// Patterns are built level by level, not by a function that calls itself (ADR-0003): level 0 is a pool of leaves, and each later level
    /// adds groups whose bodies are alternations drawn from the pool below. A pattern is then an alternation drawn from the final pool.
    private struct PatternPools {
        private var atoms: [Fragment] = []

        init(_ rng: inout SplitMix64) {
            atoms = (0 ..< 30).map { _ in Self.leaf(&rng) }
            for _ in 0 ..< 2 {
                let below = atoms
                for _ in 0 ..< 60 {
                    let inner = Self.alternation(&rng, from: below)
                    let wrapper = ["(%@)", "(?:%@)", "(?i:%@)"].randomElement(using: &rng) ?? "(%@)"
                    atoms.append(
                        Fragment(
                            text: wrapper.replacingOccurrences(of: "%@", with: inner.text), nullable: inner.nullable))
                }
            }
        }

        mutating func pattern(_ rng: inout SplitMix64) -> String { Self.alternation(&rng, from: atoms).text }

        private static func leaf(_ rng: inout SplitMix64) -> Fragment {
            switch Int.random(in: 0 ..< 4, using: &rng) {
                case 0: return Fragment(text: ".", nullable: false)
                case 1:
                    return Fragment(
                        text: ["[ab]", "[^a]", "[a-c]", "[^bc]", #"\w"#, #"\W"#].randomElement(using: &rng) ?? "[ab]",
                        nullable: false)
                default: return Fragment(text: String("abc".randomElement(using: &rng) ?? "a"), nullable: false)
            }
        }

        private static func piece(_ rng: inout SplitMix64, from pool: [Fragment]) -> Fragment {
            let base = pool[Int.random(in: 0 ..< pool.count, using: &rng)]
            guard !base.nullable, Int.random(in: 0 ..< 3, using: &rng) == 0 else { return base }
            let op = ["*", "+", "?", "*?", "+?", "??", "{2}", "{1,2}", "{0,2}?"].randomElement(using: &rng) ?? "*"
            return Fragment(
                text: base.text + op, nullable: op.hasPrefix("*") || op.hasPrefix("?") || op.hasPrefix("{0"))
        }

        private static func sequence(_ rng: inout SplitMix64, from pool: [Fragment]) -> Fragment {
            let parts = (0 ..< Int.random(in: 1 ... 4, using: &rng)).map { _ in piece(&rng, from: pool) }
            return Fragment(text: parts.map(\.text).joined(), nullable: parts.allSatisfy(\.nullable))
        }

        private static func alternation(_ rng: inout SplitMix64, from pool: [Fragment]) -> Fragment {
            let branches = (0 ..< Int.random(in: 1 ... 3, using: &rng)).map { _ in sequence(&rng, from: pool) }
            return Fragment(
                text: branches.map(\.text).joined(separator: "|"), nullable: branches.contains { $0.nullable })
        }
    }

    private static func haystack(_ rng: inout SplitMix64) -> String {
        String((0 ..< Int.random(in: 0 ... 12, using: &rng)).map { _ in "abcAB \n_".randomElement(using: &rng) ?? "a" })
    }

    @Test func `ten thousand generated pattern and haystack pairs agree with ICU`() throws {
        var rng = SplitMix64(state: 0xA3E1_2026)
        var pools = PatternPools(&rng)
        var compared = 0
        var disagreements: [String] = []
        for _ in 0 ..< 2500 {
            let source = pools.pattern(&rng)
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
