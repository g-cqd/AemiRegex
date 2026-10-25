import Foundation

@testable import AemiRegex

enum BacktrackFixture {
    static func load(_ name: String) -> [BacktrackCase] {
        guard let url = Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Resources"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [] }
        let decoder = JSONDecoder()
        return text.split(separator: "\n").compactMap { try? decoder.decode(BacktrackCase.self, from: Data($0.utf8)) }
    }
}
