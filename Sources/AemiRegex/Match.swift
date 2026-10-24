/// One match: the whole match and each capture group, as UTF-8 byte ranges of the haystack.
public struct Match: Equatable, Sendable {
    /// The range of the whole match (group 0).
    public let range: Range<Int>
    /// Groups 1 and up; empty (and not allocated) for a pattern without capture groups.
    private let captures: [Range<Int>?]

    init(range: Range<Int>, captures: [Range<Int>?] = []) {
        self.range = range
        self.captures = captures
    }

    /// Group 0 is the whole match; group `i` is the `i`th capture group, `nil` when it did not participate.
    ///
    /// - Complexity: O(group count); it builds an array. Use ``range`` or ``subscript(group:)`` on a hot path.
    public var groups: [Range<Int>?] { [range] + captures }

    /// The range of group `group` (0 is the whole match), or `nil` when it did not participate or does not exist.
    public subscript(group group: Int) -> Range<Int>? {
        if group == 0 { return range }
        return captures.indices.contains(group - 1) ? captures[group - 1] : nil
    }
}
