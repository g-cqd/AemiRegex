/// What the parser hands the compiler: the node arena, the character sets the nodes refer to, and the capture layout.
struct BTSyntaxTree: Sendable {
    var nodes: [BTNode]
    var root: Int
    var sets: [CharSet]
    var captureCount: Int
    var names: [String: Int]
}
