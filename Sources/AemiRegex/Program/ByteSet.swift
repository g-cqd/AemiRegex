/// A set of byte values, as a 256-bit bitmap.
struct ByteSet: Hashable, Sendable {
    private var words = SIMD4<UInt64>()

    init() {}

    mutating func insert(_ range: ClosedRange<UInt8>) {
        for byte in range { words[Int(byte >> 6)] |= 1 << UInt64(byte & 63) }
    }

    mutating func formUnion(_ other: ByteSet) { words |= other.words }

    /// The bytes in the set, ascending.
    var members: [UInt8] { (0 ... 255).filter { contains(UInt8($0)) }.map { UInt8($0) } }

    func contains(_ byte: UInt8) -> Bool { (words[Int(byte >> 6)] >> UInt64(byte & 63)) & 1 != 0 }
}
