/// One node of the syntax tree. Nodes live in an arena and name their children by index, so building and walking the tree needs no recursion.
struct BTNode: Sendable {
    enum Kind: Sendable {
        case empty
        /// Consumes one scalar that is in set `index`.
        case set(Int)
        case assertion(BTAssertion)
        case backReference(group: Int, ignoreCase: Bool)
        case namedBackReference(name: String, ignoreCase: Bool)
        /// A capture group (`capture` is its index) holding one child.
        case group(capture: Int)
        case concatenation
        case alternation
        /// `max == nil` is unbounded. One child.
        case repetition(min: Int, max: Int?, mode: BTRepeatMode)
        /// One child, matched without consuming; `behind` reads the text before the position.
        case look(behind: Bool, negative: Bool)
        /// One child, matched once and never re-entered.
        case atomic
        /// `(*FAIL)`: never matches.
        case fail
        /// `\K`: the match starts here.
        case keep
    }

    var kind: Kind
    var children: [Int] = []
}
