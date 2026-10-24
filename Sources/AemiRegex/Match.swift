/// One match: the whole match and each capture group, as UTF-8 byte ranges of the haystack.
public struct Match: Equatable, Sendable {
    /// Group 0 is the whole match; group `i` is `i`th capture group. `nil` when the group did not participate.
    public let groups: [Range<Int>?]

    /// The range of the whole match.
    public var range: Range<Int> { groups[0] ?? 0 ..< 0 }
}
