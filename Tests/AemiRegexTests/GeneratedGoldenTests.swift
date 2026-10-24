import Testing

@testable import AemiRegex

/// Two thousand random patterns, with assertions, flags, lazy and counted repetition and nested groups, over haystacks that include
/// newlines, word and non-word bytes and a multi-byte scalar. Go's `regexp` is the oracle; both engines must agree with it.
struct GeneratedGoldenTests {
    @Test func `the generated fixture is present and complete`() {
        #expect(GoldenFixture.generatedRows.count == 8000)
    }

    @Test(arguments: [Pattern.Engine.automatic, .pikeOnly])
    func `every generated match and capture agrees with Go`(engine: Pattern.Engine) throws {
        var compiled: [String: Pattern] = [:]
        var disagreements: [String] = []
        var checked = 0
        for row in GoldenFixture.generatedRows {
            guard let haystack = row.h else { continue }
            let pattern: Pattern
            if let cached = compiled[row.p] {
                pattern = cached
            } else {
                pattern = try Pattern(row.p, engine: engine)
                compiled[row.p] = pattern
            }
            let actual = pattern.matches(in: Array(haystack.utf8))
                .map { $0.groups.flatMap { [$0?.lowerBound ?? -1, $0?.upperBound ?? -1] } }
            checked += 1
            if actual != (row.all ?? []), disagreements.count < 10 {
                disagreements.append("/\(row.p)/ on \(haystack.debugDescription): Go \(row.all ?? []) ours \(actual)")
            }
        }
        #expect(checked == 8000)
        #expect(disagreements.isEmpty, "\(disagreements.joined(separator: "\n"))")
    }
}
