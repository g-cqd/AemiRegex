/// A scan that skips to the next position where a match could start. It may offer a position where no match starts, never skip one
/// where a match does.
struct Prefilter: Sendable {
    enum Kind: Equatable, Sendable {
        /// Every position is offered.
        case none
        /// A match starts with this byte.
        case byte(UInt8)
        /// A match starts with these two bytes.
        case pair(UInt8, UInt8)
        /// A match starts with one of these two-byte pairs (at most ``ByteScan/maxPairCount``), in ascending order.
        case pairs([BytePair])
        /// A match starts with one of these bytes (at most ``ByteScan/maxSetSize``), in ascending order.
        case set([UInt8])
    }

    let kind: Kind
    private let needles: [SIMD16<UInt8>]
    private let teddy: Teddy?

    init(_ kind: Kind) {
        self.kind = kind
        switch kind {
            case .set(let bytes):
                needles = bytes.map { SIMD16(repeating: $0) }
                teddy = nil
            case .pairs(let pairs):
                needles = []
                teddy = Teddy(pairs)
            default:
                needles = []
                teddy = nil
        }
    }

    /// The first position `>= from` that may start a match, or `nil` when none can.
    func next(in bytes: UnsafeBufferPointer<UInt8>, from: Int) -> Int? {
        switch kind {
            case .none: from <= bytes.count ? from : nil
            case .byte(let byte): unsafe ByteScan.firstIndex(of: byte, in: bytes, from: from)
            case .pair(let first, let second): unsafe ByteScan.firstIndex(ofPair: first, second, in: bytes, from: from)
            case .pairs: unsafe teddy?.firstCandidate(in: bytes, from: from)
            case .set(let set): unsafe ByteScan.firstIndex(ofAnyNeedles: needles, bytes: set, in: bytes, from: from)
        }
    }

    /// Offers candidate positions to `verify` in ascending order and returns the first non-`nil` result, or `nil` when none verifies.
    ///
    /// For a pair set the Teddy kernel reports every candidate of a window of bytes in one call, so a dense candidate stream does not
    /// pay a call and a table setup for each one. The window starts small, because a search usually stops at the first match and
    /// every candidate found past it is wasted work, and doubles while candidates keep failing, up to a few kilobytes. The batch
    /// buffer (256 positions) is on the stack.
    func firstVerified<Result>(in bytes: UnsafeBufferPointer<UInt8>, from: Int, _ verify: (Int) -> Result?) -> Result? {
        if let teddy, let base = bytes.baseAddress {
            return withUnsafeTemporaryAllocation(of: Int.self, capacity: 256) { batch -> Result? in
                var position = from
                var window = 256
                while position >= 0, position < bytes.count {
                    // Positions `position ..< position + window` are the ones this call may report; a position needs the byte after
                    // it, so the kernel is given one byte more than the window.
                    let end = min(bytes.count, position + window + 1)
                    let slice = unsafe UnsafeBufferPointer(start: base, count: end)
                    let (count, resume) = unsafe teddy.candidates(in: slice, from: position, into: batch)
                    for index in 0 ..< count {
                        if let found = verify(unsafe batch[index]) { return found }
                    }
                    if resume >= end {
                        if end == bytes.count { return nil }
                        position = end - 1
                    } else {
                        position = resume
                    }
                    window = min(window * 2, 4096)
                }
                return nil
            }
        }
        var position = from
        while let candidate = unsafe next(in: bytes, from: position) {
            if let found = verify(candidate) { return found }
            position = candidate + 1
        }
        return nil
    }

    /// The most selective scan for `program`: a literal prefix, else the set of possible first bytes, else none.
    /// A program that can match empty gets `.none`. Assertions only restrict where a match can start, so they do not hide a literal.
    init(analyzing program: Program) {
        var closure = Closure(program)
        let first = closure.consumers(from: 0)
        guard !first.reachesMatch else {
            self.init(.none)
            return
        }
        var firstBytes = ByteSet()
        for pc in first.pcs { closure.add(pc, to: &firstBytes) }
        let literal = closure.literalPrefix(maxLength: 2)
        switch literal.count {
            case 2: self.init(.pair(literal[0], literal[1]))
            case 1: self.init(.byte(literal[0]))
            default:
                if let pairs = closure.leadingPairs(limit: ByteScan.maxPairCount) {
                    self.init(.pairs(pairs))
                    return
                }
                let bytes = firstBytes.members
                self.init(bytes.count <= ByteScan.maxSetSize && !bytes.isEmpty ? .set(bytes) : .none)
        }
    }
}
