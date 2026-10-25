import Foundation

enum IRegexpFixture {
    private static func load<Row: Decodable>(_ name: String, as type: Row.Type) -> [Row] {
        guard let url = Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Resources"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [] }
        let decoder = JSONDecoder()
        return text.split(separator: "\n").compactMap { try? decoder.decode(Row.self, from: Data($0.utf8)) }
    }

    static let grammar: [IRegexpGrammarRow] = load("iregexp-grammar", as: IRegexpGrammarRow.self)
    static let golden: [IRegexpGoldenRow] = load("iregexp-golden", as: IRegexpGoldenRow.self)
}
