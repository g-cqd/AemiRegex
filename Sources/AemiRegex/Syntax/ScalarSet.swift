/// A set of Unicode scalar values, kept as sorted, non-adjacent closed ranges.
struct ScalarSet: Equatable, Sendable {
    static let maxScalar: UInt32 = 0x10FFFF

    private(set) var ranges: [ClosedRange<UInt32>]

    init() { ranges = [] }

    init(_ scalar: UInt32) { ranges = [scalar ... scalar] }

    /// Builds a set from unordered, possibly overlapping ranges.
    init(normalizing input: [ClosedRange<UInt32>]) {
        var merged: [ClosedRange<UInt32>] = []
        merged.reserveCapacity(input.count)
        for range in input.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = merged.last, range.lowerBound <= last.upperBound &+ 1 {
                if range.upperBound > last.upperBound {
                    merged[merged.count - 1] = last.lowerBound ... range.upperBound
                }
            } else {
                merged.append(range)
            }
        }
        ranges = merged
    }

    var isEmpty: Bool { ranges.isEmpty }

    func union(_ other: ScalarSet) -> ScalarSet { ScalarSet(normalizing: ranges + other.ranges) }

    /// Every scalar value in `0 ... 0x10FFFF` that is not in the set. Surrogates are left in: no UTF-8 sequence encodes them, so
    /// compiling the set drops them.
    func negated() -> ScalarSet {
        var result: [ClosedRange<UInt32>] = []
        result.reserveCapacity(ranges.count + 1)
        var next: UInt32 = 0
        for range in ranges {
            if range.lowerBound > next { result.append(next ... range.lowerBound - 1) }
            next = range.upperBound &+ 1
        }
        if next <= Self.maxScalar { result.append(next ... Self.maxScalar) }
        return ScalarSet(normalizing: result)
    }

    /// The set plus the other-case ASCII letter of each ASCII letter in it.
    ///
    /// Only ASCII letters fold; full Unicode simple case folding is not implemented yet.
    func foldedASCII() -> ScalarSet {
        var extra: [ClosedRange<UInt32>] = []
        for range in ranges {
            if range.overlaps(0x61 ... 0x7A) {
                let lower = range.clamped(to: 0x61 ... 0x7A)
                extra.append((lower.lowerBound - 32) ... (lower.upperBound - 32))
            }
            if range.overlaps(0x41 ... 0x5A) {
                let upper = range.clamped(to: 0x41 ... 0x5A)
                extra.append((upper.lowerBound + 32) ... (upper.upperBound + 32))
            }
        }
        return extra.isEmpty ? self : ScalarSet(normalizing: ranges + extra)
    }

    /// `\n`, the one scalar `.` does not match by default.
    static let newline = ScalarSet(0x0A)
}
