import Foundation

/// One line of `iregexp-grammar.jsonl`: whether the RFC 9485 grammar accepts the pattern (a recogniser written from the ABNF in Go), and,
/// for a grammar-valid pattern, whether Go compiles the RFC's mapping (`a{3,2}` is in the grammar but runs nowhere).
struct IRegexpGrammarRow: Decodable {
    let p: String
    let valid: Bool
    let compiles: Bool?
}

/// One line of `iregexp-golden.jsonl`: Go's answers for the RFC's mapping of a grammar-valid pattern.
struct IRegexpGoldenRow: Decodable {
    let p: String
    let h: String?
    let full: Bool?
    let all: [[Int]]?
    let error: Bool?
}

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
