/// The code for one node, with what the compiler needs to know about it when it is part of a larger node.
struct BTFragment {
    var code: [BTInstruction]
    /// Whether the node can match the empty string.
    var canBeEmpty: Bool
    /// The capture groups the code contains, as `lowest ..< highest + 1`, or `nil` when it has none.
    var groups: Range<Int>?
    /// The fewest and most scalars the node can consume (`nil` for no upper bound); PCRE2 needs them to read a look-behind forward.
    var minLength = 0
    var maxLength: Int? = 0

    static func joining(_ parts: [BTFragment], backward: Bool) -> BTFragment {
        var code: [BTInstruction] = []
        var empty = true
        var groups: Range<Int>?
        var shortest = 0
        var longest: Int? = 0
        for part in backward ? parts.reversed() : parts {
            code += part.code
            empty = empty && part.canBeEmpty
            groups = merged(groups, part.groups)
            shortest += part.minLength
            longest = longest.flatMap { total in part.maxLength.map { total + $0 } }
        }
        return BTFragment(code: code, canBeEmpty: empty, groups: groups, minLength: shortest, maxLength: longest)
    }

    static func merged(_ a: Range<Int>?, _ b: Range<Int>?) -> Range<Int>? {
        guard let a else { return b }
        guard let b else { return a }
        return min(a.lowerBound, b.lowerBound) ..< max(a.upperBound, b.upperBound)
    }
}
