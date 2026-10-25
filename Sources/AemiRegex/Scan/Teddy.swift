import CAemiRegex

/// The table of a two-byte Teddy kernel for a set of byte pairs, and the scan that uses it.
///
/// A position it offers may not be a pair (pairs that share a bucket accept each other's nibbles), but it never skips one that is.
struct Teddy: Sendable {
    private let table: [UInt8]

    /// - Parameter pairs: The pairs to find. Pair `k` goes to bucket `k % 8`, so up to eight pairs are exact apart from nibble
    ///   cross-products, and more only add false candidates.
    init(_ pairs: [BytePair]) {
        var table = [UInt8](repeating: 0, count: Int(AEMIRE_TEDDY2_TABLE_BYTES))
        for (index, pair) in pairs.enumerated() {
            let bucket = UInt8(1) << UInt8(index % 8)
            table[Int(pair.first & 15)] |= bucket
            table[16 + Int(pair.first >> 4)] |= bucket
            table[32 + Int(pair.second & 15)] |= bucket
            table[48 + Int(pair.second >> 4)] |= bucket
        }
        self.table = table
    }

    /// The first position `>= from` that may start one of the pairs, or `nil`.
    ///
    /// The C result is checked before it is used: a position below `from` or without a following byte would let a caller index out of
    /// bounds, so it stops the program instead (the kernel's own invariant is false, and nothing downstream can be trusted).
    func firstCandidate(in bytes: UnsafeBufferPointer<UInt8>, from: Int) -> Int? {
        guard from >= 0, from <= bytes.count, let base = bytes.baseAddress else { return nil }
        let found = table.withUnsafeBufferPointer { unsafe aemire_teddy2_find($0.baseAddress, base, bytes.count, from) }
        return Self.checked(found, from: from, count: bytes.count)
    }

    /// The scalar reference of ``firstCandidate(in:from:)``: the same candidates, one byte at a time. For tests.
    func firstCandidateScalar(in bytes: UnsafeBufferPointer<UInt8>, from: Int) -> Int? {
        guard from >= 0, from <= bytes.count, let base = bytes.baseAddress else { return nil }
        let found = table.withUnsafeBufferPointer {
            unsafe aemire_teddy2_find_scalar($0.baseAddress, base, bytes.count, from)
        }
        return Self.checked(found, from: from, count: bytes.count)
    }

    /// Every candidate from `from` on, ascending, written to `out` (at most `out.count`), in one call.
    /// - Returns: How many were written, and where to continue; the scan is complete when that is `bytes.count` or more.
    ///
    /// The count and the resume position are checked before they are returned: the C side writes only inside `out`, but a wrong count
    /// would still let a caller read stale entries, so a violated invariant stops the program.
    func candidates(
        in bytes: UnsafeBufferPointer<UInt8>, from: Int, into out: UnsafeMutableBufferPointer<Int>
    ) -> (count: Int, resume: Int) {
        precondition(out.count >= 1, "the Teddy batch needs room for at least one candidate")
        guard from >= 0, from < bytes.count, let base = bytes.baseAddress, let target = out.baseAddress else {
            return (0, bytes.count)
        }
        var resume = 0
        let count = table.withUnsafeBufferPointer {
            unsafe aemire_teddy2_candidates($0.baseAddress, base, bytes.count, from, target, out.count, &resume)
        }
        precondition(count >= 0 && count <= out.count, "the Teddy batch wrote \(count) of \(out.count)")
        precondition(resume > from || resume >= bytes.count, "the Teddy batch made no progress")
        return (count, resume)
    }

    /// `SIZE_MAX` (imported as -1) means none; anything else must be a position with a following byte, at or after `from`.
    private static func checked(_ found: Int, from: Int, count: Int) -> Int? {
        if found == -1 { return nil }
        precondition(
            found >= from && found + 1 < count, "the Teddy kernel returned \(found) for from \(from), count \(count)")
        return found
    }
}
