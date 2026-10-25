/// Mapping a match back to the `String` or `Substring` it was found in.
extension Match {
    /// The whole match as a range in `text`.
    ///
    /// - Precondition: `text` is the text this match was found in (or has the same UTF-8 up to the match's end).
    // @dl:accept -- range and checkedRange provide the trapping and checked variants of the same accessors
    public func range<S: StringProtocol>(in text: S) -> Range<S.Index> {
        Self.indices(range, in: text)
    }

    /// Group `group`'s range in `text`, or `nil` when it did not take part or does not exist.
    public func range<S: StringProtocol>(ofGroup group: Int, in text: S) -> Range<S.Index>? {
        self[group: group].map { Self.indices($0, in: text) }
    }

    // @dl:accept -- range and checkedRange provide the trapping and checked variants of the same accessors
    /// The whole match as a range in `text`, or `nil` if `text` is too short or the byte offsets fall outside it.
    public func checkedRange<S: StringProtocol>(in text: S) -> Range<S.Index>? {
        Self.checkedIndices(range, in: text)
    }

    /// Group `group`'s range in `text`, or `nil` if the group did not take part, or the byte offsets fall outside it.
    public func checkedRange<S: StringProtocol>(ofGroup group: Int, in text: S) -> Range<S.Index>? {
        self[group: group].flatMap { Self.checkedIndices($0, in: text) }
    }

    private static func indices<S: StringProtocol>(_ bytes: Range<Int>, in text: S) -> Range<S.Index> {
        let utf8 = text.utf8
        let lower = utf8.index(utf8.startIndex, offsetBy: bytes.lowerBound)
        return lower ..< utf8.index(lower, offsetBy: bytes.count)
    }

    private static func checkedIndices<S: StringProtocol>(_ bytes: Range<Int>, in text: S) -> Range<S.Index>? {
        let utf8 = text.utf8
        guard bytes.lowerBound >= 0,
            let lower = utf8.index(utf8.startIndex, offsetBy: bytes.lowerBound, limitedBy: utf8.endIndex),
            let upper = utf8.index(lower, offsetBy: bytes.count, limitedBy: utf8.endIndex)
        else { return nil }
        return lower ..< upper
    }
}
