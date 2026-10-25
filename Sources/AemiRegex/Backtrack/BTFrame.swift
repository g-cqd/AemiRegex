/// One open group while parsing. Its items are the nodes of the branch being read; finished branches wait in `branches`.
struct BTFrame {
    enum Kind: Equatable {
        case root
        /// A group; `capture` is its index, or `nil` for `(?:…)`.
        case group(capture: Int?)
        case look(behind: Bool, negative: Bool)
        case atomic
        /// PCRE2 `(?(condition)yes|no)`.
        case conditional
    }

    /// Distinguishes this group from every other, so a name can be told to be in different alternatives (see ``BTParser``).
    var id = 0
    var kind: Kind
    /// Byte offset of the opening parenthesis, for errors.
    var openOffset: Int
    /// The flags to restore when the group closes.
    var savedFlags: BTFlags
    var branches: [Int] = []
    var items: [Int] = []
    /// Whether the last item already carries a quantifier, so a second one is an error.
    var lastIsQuantified = false
    /// For PCRE2's branch reset `(?|…)`: the group count at its start, and the highest count any branch reached. Every branch numbers
    /// its groups from the start.
    var resetStart: Int?
    var resetHighest = 0
    /// For a conditional: what it tests, and for a look-around condition the node of the look-around once it has closed.
    var condition: BTCondition?
    var conditionNode: Int?
}
