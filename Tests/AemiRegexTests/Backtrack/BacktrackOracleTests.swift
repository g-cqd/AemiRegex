import Testing

@testable import AemiRegex

/// The backtracker agrees with the oracles on generated and hand-picked patterns (`curated.json`): `node` for ECMAScript (flags `du`), `libpcre2` in UTF mode for PCRE2.
/// The fixtures come from `Scripts/oracle/backtrack-fixtures.js`; the same seed gives the same file.
struct BacktrackOracleTests {
    @Test(arguments: [
        ("backtrack-ecma", BacktrackingPattern.Dialect.ecmaScript),
        ("backtrack-pcre2", BacktrackingPattern.Dialect.pcre2),
        ("backtrack-curated-ecma", BacktrackingPattern.Dialect.ecmaScript),
        ("backtrack-curated-pcre2", BacktrackingPattern.Dialect.pcre2)
    ])
    func `the backtracker agrees with the oracle on generated and curated patterns`(
        fixture: String, dialect: BacktrackingPattern.Dialect
    ) {
        let cases = BacktrackFixture.load(fixture)
        #expect(cases.count >= 300, "the fixture \(fixture) must load")
        let report = BacktrackConformance.run(cases, dialect: dialect)
        #expect(
            report.mismatches.isEmpty, "\(report.mismatches.count) of \(cases.count): \(report.mismatches.prefix(12))")
        let ranOutOfBudget = report.skipped.filter { $0.hasPrefix("budget") }
        #expect(ranOutOfBudget.isEmpty, "\(ranOutOfBudget.count) cases used up the budget: \(ranOutOfBudget.prefix(6))")
        #expect(report.skipped.count * 50 < cases.count, "skipped \(report.skipped.count): \(report.skipped.prefix(6))")
    }
}
