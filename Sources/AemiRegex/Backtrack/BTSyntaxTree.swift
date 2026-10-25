/// What the parser hands the compiler: the node arena, the character sets the nodes refer to, and the capture layout.
struct BTSyntaxTree: Sendable {
    var nodes: [BTNode]
    var root: Int
    var sets: [CharSet]
    var captureCount: Int
    /// Each group name with the groups that have it, in order: only ECMAScript allows more than one, in different alternatives.
    var names: [String: [Int]]
}
