/// What the byte before or after a position is, as an assertion sees it. 0 is the edge of the text.
enum NeighborContext {
    static let edge = 0
    static let newline = 1
    static let word = 2
    static let other = 3

    /// The context of a byte.
    static func of(_ byte: UInt8) -> Int {
        switch byte {
            case 0x0A: newline
            case 0x30 ... 0x39, 0x41 ... 0x5A, 0x5F, 0x61 ... 0x7A: word
            default: other
        }
    }

    /// Whether `assertion` holds between a position's previous and next neighbours.
    static func holds(_ assertion: Assertion, previous: Int, next: Int) -> Bool {
        switch assertion {
            case .beginText: previous == edge
            case .endText: next == edge
            case .beginLine: previous == edge || previous == newline
            case .endLine: next == edge || next == newline
            case .wordBoundary: (previous == word) != (next == word)
            case .notWordBoundary: (previous == word) == (next == word)
        }
    }
}
