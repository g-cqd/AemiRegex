/// Mapping a match back to the `String` it was found in.
extension Match {
    /// The whole match as a range of `string`.
    ///
    /// - Precondition: `string` is the text this match was found in (or has the same UTF-8 up to the match's end).
    public func range(in string: String) -> Range<String.Index> { Self.indices(range, in: string) }

    /// Group `group`'s range in `string`, or `nil` when it did not take part or does not exist.
    public func range(ofGroup group: Int, in string: String) -> Range<String.Index>? {
        self[group: group].map { Self.indices($0, in: string) }
    }

    private static func indices(_ bytes: Range<Int>, in string: String) -> Range<String.Index> {
        let utf8 = string.utf8
        let lower = utf8.index(utf8.startIndex, offsetBy: bytes.lowerBound)
        return lower ..< utf8.index(lower, offsetBy: bytes.count)
    }
}
