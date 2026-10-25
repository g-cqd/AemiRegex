import Foundation

/// One line of `iregexp-golden.jsonl`: Go's answers for the RFC's mapping of a grammar-valid pattern.
struct IRegexpGoldenRow: Decodable {
    let p: String
    let h: String?
    let full: Bool?
    let all: [[Int]]?
    let error: Bool?
}
