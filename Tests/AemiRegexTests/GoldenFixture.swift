import Foundation
import Testing

enum GoldenFixture {
    /// Rows in file order; empty when the fixture cannot be read (a test asserts that it is not).
    static let rows: [GoldenRow] = load("re2-golden")

    /// Random patterns with assertions and flags, from `Scripts/golden/generated/gen.go`.
    static let generatedRows: [GoldenRow] = load("re2-generated")

    private static func load(_ name: String) -> [GoldenRow] {
        guard let url = Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Resources"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [] }
        let decoder = JSONDecoder()
        return text.split(separator: "\n").compactMap { try? decoder.decode(GoldenRow.self, from: Data($0.utf8)) }
    }

    static let validPatterns: [GoldenPattern] = {
        var order: [String] = []
        var cases: [String: [(String, [[Int]])]] = [:]
        for row in rows where row.error != true {
            guard let h = row.h else { continue }
            if cases[row.p] == nil { order.append(row.p) }
            cases[row.p, default: []].append((h, row.all ?? []))
        }
        return order.map { GoldenPattern(pattern: $0, cases: cases[$0] ?? []) }
    }()

    static let invalidPatterns: [String] = rows.filter { $0.error == true }.map(\.p)
}
