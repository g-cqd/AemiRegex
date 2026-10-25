/// A pattern decoded into Unicode scalars, with the UTF-8 byte offset of each, so errors can name where in the text the caller wrote.
struct PatternText {
    let scalars: [UInt32]
    /// `offsets[i]` is the UTF-8 offset of `scalars[i]`; the last entry is the pattern's length in bytes.
    let offsets: [Int]

    init(_ pattern: String) {
        var scalars: [UInt32] = []
        var offsets: [Int] = []
        scalars.reserveCapacity(pattern.utf8.count)
        offsets.reserveCapacity(pattern.utf8.count + 1)
        var offset = 0
        for scalar in pattern.unicodeScalars {
            scalars.append(scalar.value)
            offsets.append(offset)
            offset += scalar.utf8.count
        }
        offsets.append(offset)
        self.scalars = scalars
        self.offsets = offsets
    }

    /// The byte offset of scalar `index`; an index past the end gives the length.
    func offset(_ index: Int) -> Int { offsets[min(index, offsets.count - 1)] }
}
