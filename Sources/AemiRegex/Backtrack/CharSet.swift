internal import AemiUnicode

/// A set of scalars with a bitmap for ASCII, which is most of what a search tests.
struct CharSet: Sendable {
    private let low: UInt64
    private let high: UInt64
    let scalars: UnicodeScalarSet

    init(_ scalars: UnicodeScalarSet) {
        self.scalars = scalars
        var low: UInt64 = 0
        var high: UInt64 = 0
        for range in scalars.ranges where range.lowerBound < 128 {
            for value in range.lowerBound ... min(range.upperBound, 127) {
                if value < 64 { low |= 1 << UInt64(value) } else { high |= 1 << UInt64(value - 64) }
            }
        }
        self.low = low
        self.high = high
    }

    /// - Complexity: O(1) for ASCII, O(log ranges) otherwise.
    func contains(_ value: UInt32) -> Bool {
        if value < 64 { return low & (1 << UInt64(value)) != 0 }
        if value < 128 { return high & (1 << UInt64(value - 64)) != 0 }
        return scalars.contains(value)
    }
}
