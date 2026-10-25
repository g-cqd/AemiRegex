import Foundation

/// One line of `re2-golden.jsonl`, written by `Scripts/golden/gen.go` from Go's `regexp` package.
struct GoldenRow: Decodable {
    let p: String
    let h: String?
    let all: [[Int]]?
    let error: Bool?
}
