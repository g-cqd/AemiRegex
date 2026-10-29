internal import AemiKernels

/// The scans for the first position of a byte, a byte pair, or any byte of a small set, from a start offset: AemiKernels' kernels
/// (ADR-0013). The single byte is `memchr`; the set and the pair are AemiKernels' inlinable Swift SIMD scans, which cost no call where a
/// prefilter calls them once per candidate.
enum ByteScan {
    /// The largest set a prefilter scans for; a larger set offers too many candidates to be worth it.
    static let maxSetSize = 8

    /// The most byte pairs a ``Prefilter`` keeps: more pairs share buckets in the Teddy table and give mostly false candidates.
    static let maxPairCount = 16

    /// The first index `>= from` whose byte is `byte`, or `nil`.
    static func firstIndex(of byte: UInt8, in bytes: UnsafeBufferPointer<UInt8>, from: Int) -> Int? {
        guard from >= 0, from <= bytes.count, let base = bytes.baseAddress else { return nil }
        let rest = bytes.count - from
        let found = unsafe AemiKernels.firstIndexOfByte(base: base + from, count: rest, needle: byte)
        return found < rest ? from + found : nil
    }

    /// The first index `i >= from` with `bytes[i] == first && bytes[i + 1] == second`, or `nil`.
    static func firstIndex(ofPair first: UInt8, _ second: UInt8, in bytes: UnsafeBufferPointer<UInt8>, from: Int)
        -> Int?
    {
        unsafe AemiKernels.firstIndex(ofPair: first, second, in: bytes, from: from)
    }

    /// The first index `>= from` whose byte is in `set`, or `nil`. `set` holds at most ``maxSetSize`` bytes. For tests: a prefilter
    /// builds its set once.
    static func firstIndex(ofAny set: [UInt8], in bytes: UnsafeBufferPointer<UInt8>, from: Int) -> Int? {
        precondition(set.count <= maxSetSize, "a prefilter set holds at most \(maxSetSize) bytes")
        guard let small = AemiKernels.SmallByteSet(set) else { return from >= 0 && from <= bytes.count ? from : nil }
        return unsafe small.firstIndex(in: bytes, from: from)
    }
}
