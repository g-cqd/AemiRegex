/// Searching a `String`: its UTF-8 is read in place when the string stores it contiguously (a native Swift string does), and copied once
/// when it does not (a bridged `NSString`). Matches are the same `Match` values as for bytes; ``Match/range(in:)`` maps them back.
extension Pattern {
    /// Runs `body` on the UTF-8 of `string`: in place when contiguous, else on a copy.
    private func withUTF8<Result>(_ string: String, _ body: (ByteBuffer) -> Result) -> Result {
        if let result = string.utf8.withContiguousStorageIfAvailable({ unsafe body(ByteBuffer($0)) }) { return result }
        return Array(string.utf8).withUnsafeBufferPointer { unsafe body(ByteBuffer($0)) }
    }

    /// The leftmost match in `string` that starts at or after `start` (the start of the string when `nil`).
    ///
    /// - Parameters:
    ///   - string: The text to search.
    ///   - start: An index of `string`; assertions such as `^` and `\b` see the characters before it.
    /// - Returns: The match, or `nil`. Use ``Match/range(in:)`` for `String.Index` ranges.
    /// - Complexity: As ``firstMatch(in:from:)``; converting `start` is O(1) for a native string and O(n) otherwise.
    public func firstMatch(in string: String, from start: String.Index? = nil) -> Match? {
        let offset = start.map { string.utf8.distance(from: string.utf8.startIndex, to: $0) } ?? 0
        return withUTF8(string) { firstMatch(inBuffer: $0, from: offset) }
    }

    /// Every non-overlapping match in `string`, left to right (see ``matches(in:)-([UInt8])``).
    public func matches(in string: String) -> [Match] {
        var result: [Match] = []
        forEachMatch(in: string) { match in
            result.append(match)
            return true
        }
        return result
    }

    /// Calls `body` with each match in `string`; return `false` to stop. Allocates nothing per match for a pattern without captures.
    public func forEachMatch(in string: String, _ body: (Match) -> Bool) {
        withUTF8(string) { forEachMatch(inBuffer: $0, body) }
    }

    /// The number of matches in `string`, counted without building them; capture groups are not computed.
    public func matchCount(in string: String) -> Int {
        var count = 0
        withUTF8(string) { buffer in
            forEachMatch(inBuffer: buffer, needsCaptures: false) { _ in
                count += 1
                return true
            }
        }
        return count
    }

    /// Whether there is a match in `string`. For a whole-string pattern: whether the whole string is one.
    public func isMatch(in string: String) -> Bool {
        withUTF8(string) { firstMatch(inBuffer: $0, from: 0, needsCaptures: false) != nil }
    }
}
