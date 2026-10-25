import Foundation

/// One line of `iregexp-grammar.jsonl`: whether the RFC 9485 grammar accepts the pattern (a recogniser written from the ABNF in Go), and,
/// for a grammar-valid pattern, whether Go compiles the RFC's mapping (`a{3,2}` is in the grammar but runs nowhere).
struct IRegexpGrammarRow: Decodable {
    let p: String
    let valid: Bool
    let compiles: Bool?
}
