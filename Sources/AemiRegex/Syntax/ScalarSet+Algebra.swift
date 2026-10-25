extension ScalarSet {
    /// The scalars in both sets.
    /// - Complexity: O(ranges of both).
    func intersection(_ other: ScalarSet) -> ScalarSet {
        var result: [ClosedRange<UInt32>] = []
        var left = 0
        var right = 0
        while left < ranges.count, right < other.ranges.count {
            let (a, b) = (ranges[left], other.ranges[right])
            let low = max(a.lowerBound, b.lowerBound)
            let high = min(a.upperBound, b.upperBound)
            if low <= high { result.append(low ... high) }
            if a.upperBound < b.upperBound { left += 1 } else { right += 1 }
        }
        return ScalarSet(normalizing: result)
    }

    /// The scalars in this set and not in `other`.
    func subtracting(_ other: ScalarSet) -> ScalarSet { intersection(other.negated()) }
}
