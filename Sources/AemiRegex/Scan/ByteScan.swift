/// SIMD scans for the first position of a byte, a byte pair, or any byte of a small set.
///
/// These replace per-byte loops where a regex can only start at a few byte values. On arm64 the compare lowers to `cmeq.16b`; on
/// x86_64 to `pcmpeqb`. A probe (`docs/research/neon-assembly-2026-10.md`) found Swift SIMD within 1.0 to 1.4x of C NEON intrinsics,
/// so no assembly is used.
///
/// Memory safety: every load reads 16 bytes at an index `i` only after checking `i + 16 <= count` (or `i + 17 <= count` for the
/// shifted load of a pair scan), so no read passes `baseAddress + count`. The tests cover every length around the vector widths
/// and every start offset.
enum ByteScan {
    /// The maximum set size `firstIndex(ofAny:…)` handles; a larger set costs more compares than a table lookup per byte.
    static let maxSetSize = 8

    private static let weights = SIMD16<UInt8>(1, 2, 4, 8, 16, 32, 64, 128, 1, 2, 4, 8, 16, 32, 64, 128)

    /// The first index `>= from` whose byte is `byte`, or `nil`.
    static func firstIndex(of byte: UInt8, in bytes: UnsafeBufferPointer<UInt8>, from: Int) -> Int? {
        unsafe firstIndex(ofAnyNeedles: [SIMD16(repeating: byte)], bytes: [byte], in: bytes, from: from)
    }

    /// The first index `i >= from` with `bytes[i] == first && bytes[i + 1] == second`, or `nil`.
    static func firstIndex(ofPair first: UInt8, _ second: UInt8, in bytes: UnsafeBufferPointer<UInt8>, from: Int)
        -> Int?
    {
        guard from >= 0, from <= bytes.count, let base = bytes.baseAddress else { return nil }
        let count = bytes.count
        let a = SIMD16<UInt8>(repeating: first)
        let b = SIMD16<UInt8>(repeating: second)
        var i = from
        while i + 17 <= count {
            let hit = unsafe (load(base, i) .== a) .& (load(base, i + 1) .== b)
            if any(hit) { return i + firstSet(hit) }
            i += 16
        }
        while i + 1 < count {
            if unsafe base[i] == first, unsafe base[i + 1] == second { return i }
            i += 1
        }
        return nil
    }

    /// The first index `>= from` whose byte is in `set`, or `nil`. `set` holds at most ``maxSetSize`` bytes.
    static func firstIndex(ofAny set: [UInt8], in bytes: UnsafeBufferPointer<UInt8>, from: Int) -> Int? {
        precondition(
            set.count <= maxSetSize, "a set larger than \(maxSetSize) bytes needs a table lookup, not a compare each")
        return unsafe firstIndex(ofAnyNeedles: set.map { SIMD16(repeating: $0) }, bytes: set, in: bytes, from: from)
    }

    /// The scan behind all three single-position entry points. `needles` are the broadcast bytes of `set`.
    static func firstIndex(
        ofAnyNeedles needles: [SIMD16<UInt8>], bytes set: [UInt8], in bytes: UnsafeBufferPointer<UInt8>, from: Int
    ) -> Int? {
        guard from >= 0, from <= bytes.count, let base = bytes.baseAddress else { return nil }
        let count = bytes.count
        var i = from
        while i + 16 <= count {
            let chunk = unsafe load(base, i)
            let hit = needles.dropFirst().reduce(chunk .== needles[0]) { $0 .| (chunk .== $1) }
            if any(hit) { return i + firstSet(hit) }
            i += 16
        }
        while i < count {
            if set.contains(unsafe base[i]) { return i }
            i += 1
        }
        return nil
    }

    private static func load(_ base: UnsafePointer<UInt8>, _ index: Int) -> SIMD16<UInt8> {
        unsafe UnsafeRawPointer(base + index).loadUnaligned(as: SIMD16<UInt8>.self)
    }

    /// The index of the first true lane. NEON has no movemask, so the lanes are weighted and summed per half instead.
    private static func firstSet(_ mask: SIMDMask<SIMD16<Int8>>) -> Int {
        let weighted = SIMD16<UInt8>(repeating: 0).replacing(with: weights, where: mask)
        let bits = UInt32(weighted.lowHalf.wrappedSum()) | (UInt32(weighted.highHalf.wrappedSum()) << 8)
        return bits.trailingZeroBitCount
    }
}
