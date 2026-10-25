import Testing

/// All haystacks that Go ran for one valid pattern, with the answer Go gave.
struct GoldenPattern: Sendable, CustomTestStringConvertible {
    let pattern: String
    let cases: [(haystack: String, all: [[Int]])]
    var testDescription: String { "/\(pattern)/" }
}
