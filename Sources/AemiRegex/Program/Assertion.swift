/// A zero-width condition on the position.
enum Assertion: UInt8, Sendable {
    case beginText, endText, beginLine, endLine, wordBoundary, notWordBoundary

    /// The assertion as seen when the text is read backwards: edges swap, word boundaries do not.
    var mirrored: Assertion {
        switch self {
            case .beginText: .endText
            case .endText: .beginText
            case .beginLine: .endLine
            case .endLine: .beginLine
            case .wordBoundary, .notWordBoundary: self
        }
    }
}
