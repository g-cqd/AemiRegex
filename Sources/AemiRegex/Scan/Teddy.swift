internal import AemiKernels

/// The multi-literal prefilter's pair scan: AemiKernels' two-byte Teddy kernel (`AemiKernels.PairSet`, ADR-0013), over the prefilter's
/// pairs. A position it offers may not be a pair, but it never skips one that is.
struct Teddy: Sendable {
    private let set: AemiKernels.PairSet

    /// - Parameter pairs: The pairs to find. Pair `k` goes to bucket `k % 8`.
    init(_ pairs: [BytePair]) {
        set = AemiKernels.PairSet(pairs.map { (first: $0.first, second: $0.second) })
    }

    /// The first position `>= from` that may start one of the pairs, or `nil`.
    func firstCandidate(in bytes: UnsafeBufferPointer<UInt8>, from: Int) -> Int? {
        unsafe set.firstCandidate(in: bytes, from: from)
    }

    /// The scalar reference of ``firstCandidate(in:from:)``. For tests.
    func firstCandidateScalar(in bytes: UnsafeBufferPointer<UInt8>, from: Int) -> Int? {
        unsafe set.firstCandidate(in: bytes, from: from, backend: .scalar)
    }

    /// Every candidate from `from` on, ascending, written to `out`. - Returns: how many, and where to continue.
    func candidates(
        in bytes: UnsafeBufferPointer<UInt8>, from: Int, into out: UnsafeMutableBufferPointer<Int>
    ) -> (count: Int, resume: Int) {
        unsafe set.candidates(in: bytes, from: from, into: out)
    }
}
