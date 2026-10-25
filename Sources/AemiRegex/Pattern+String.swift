/// Searching a `String` or `Substring`: its UTF-8 is read in place when the string stores it contiguously (a native Swift string does),
/// and copied once when it does not (a bridged `NSString`). Matches are the same `Match` values as for bytes; ``Match/range(in:)`` maps them back.
extension Pattern {
    /// Runs `body` on the UTF-8 of `text`: in place when contiguous, else on a copy.
    private func withUTF8<S: StringProtocol, Result>(_ text: S, _ body: (ByteBuffer) -> Result) -> Result {
        if let result = text.utf8.withContiguousStorageIfAvailable({ unsafe body(ByteBuffer($0)) }) {
            return result
        }
        return Array(text.utf8).withUnsafeBufferPointer { unsafe body(ByteBuffer($0)) }
    }

    /// The leftmost match in `text` that starts at or after `start` (the start of the text when `nil`).
    ///
    /// - Parameters:
    ///   - text: The text to search (`String` or `Substring`).
    ///   - start: An index of `text`; assertions such as `^` and `\b` see the characters before it.
    /// - Returns: The match, or `nil`. Use ``Match/range(in:)`` for `String.Index` ranges.
    /// - Complexity: As ``firstMatch(in:from:)``; converting `start` is O(1) for a native string and O(n) otherwise.
    public func firstMatch<S: StringProtocol>(in text: S, from start: S.Index? = nil) -> Match? {
        let offset = start.map { text.utf8.distance(from: text.utf8.startIndex, to: $0) } ?? 0
        return withUTF8(text) { firstMatch(inBuffer: $0, from: offset) }
    }

    /// Every non-overlapping match in `text`, left to right (see ``matches(in:)-([UInt8])``).
    public func matches<S: StringProtocol>(in text: S) -> [Match] {
        var result: [Match] = []
        forEachMatch(in: text) { match in
            result.append(match)
            return true
        }
        return result
    }

    /// Calls `body` with each match in `text`; return `false` to stop. Allocates nothing per match for a pattern without captures.
    public func forEachMatch<S: StringProtocol>(in text: S, _ body: (Match) -> Bool) {
        withUTF8(text) { forEachMatch(inBuffer: $0, body) }
    }

    /// The number of matches in `text`, counted without building them; capture groups are not computed.
    public func matchCount<S: StringProtocol>(in text: S) -> Int {
        var count = 0
        withUTF8(text) { buffer in
            forEachMatch(inBuffer: buffer, needsCaptures: false) { _ in
                count += 1
                return true
            }
        }
        return count
    }

    /// Whether there is a match in `text`. For a whole-string pattern: whether the whole text is one.
    public func isMatch<S: StringProtocol>(in text: S) -> Bool {
        withUTF8(text) { firstMatch(inBuffer: $0, from: 0, needsCaptures: false) != nil }
    }
}
