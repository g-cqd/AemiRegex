/// What a PCRE2 conditional group `(?(…)yes|no)` tests.
enum BTCondition: Equatable, Sendable {
    case group(Int)
    case namedGroup(String)
    /// Inside a recursion or subroutine call: of group `n`, or of any when `nil`.
    case recursion(Int?)
    /// `(?(DEFINE)…)`: groups that exist only to be called; the body never runs where it stands.
    case define
    /// An assertion such as `(?(?=a)…)`: the first child of the node.
    case lookaround
}
