internal import AemiKernel
internal import AemiUnicode

/// Turns a set of scalar values into instructions that match one UTF-8 encoded member.
struct ClassCompiler {
    private(set) var sets: ContiguousArray<ByteBitmap> = []
    private var index: [ByteBitmap: Int] = [:]

    /// The instructions for `set`; with `reversed`, each UTF-8 sequence is matched last byte first. An empty set compiles to an instruction that never matches.
    mutating func compile(_ set: UnicodeScalarSet, reversed: Bool = false) -> [Instruction] {
        var branches: [[Instruction]] = []
        let ascii = set.ranges.compactMap { range -> ClosedRange<UInt32>? in
            range.overlaps(0 ... 0x7F) ? range.clamped(to: 0 ... 0x7F) : nil
        }
        if ascii.count == 1, let only = ascii.first {
            branches.append([.byteRange(UInt8(only.lowerBound), UInt8(only.upperBound))])
        } else if !ascii.isEmpty {
            var bytes = ByteBitmap()
            for range in ascii { bytes.insert(UInt8(range.lowerBound) ... UInt8(range.upperBound)) }
            branches.append([.byteSet(intern(bytes))])
        }
        for range in set.ranges where range.upperBound > 0x7F {
            let clipped = range.clamped(to: 0x80 ... UnicodeScalarSet.maxScalar)
            for sequence in UTF8RangeSequences.sequences(clipped) {
                branches.append(
                    (reversed ? sequence.reversed() : sequence).map { .byteRange($0.lowerBound, $0.upperBound) })
            }
        }
        if branches.isEmpty { return [.byteSet(intern(ByteBitmap()))] }
        return Fragment.alternation(branches)
    }

    private mutating func intern(_ set: ByteBitmap) -> Int {
        if let existing = index[set] { return existing }
        sets.append(set)
        index[set] = sets.count - 1
        return sets.count - 1
    }
}
