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
    private let secondNeedles: [SIMD16<UInt8>]

    init(_ kind: Kind) {
        self.kind = kind
        switch kind {
            case .set(let bytes):
                needles = bytes.map { SIMD16(repeating: $0) }
                secondNeedles = []
            case .pairs(let pairs):
                needles = pairs.map { SIMD16(repeating: $0.first) }
                secondNeedles = pairs.map { SIMD16(repeating: $0.second) }
            default:
                needles = []
                secondNeedles = []
        }
    }

    /// The first position `>= from` that may start a match, or `nil` when none can.
    func next(in bytes: UnsafeBufferPointer<UInt8>, from: Int) -> Int? {
        switch kind {
            case .none: from <= bytes.count ? from : nil
            case .byte(let byte): unsafe ByteScan.firstIndex(of: byte, in: bytes, from: from)
            case .pair(let first, let second): unsafe ByteScan.firstIndex(ofPair: first, second, in: bytes, from: from)
            case .pairs(let pairs):
                unsafe ByteScan.firstIndex(
                    ofAnyPairNeedles: needles, secondNeedles, pairs: pairs, in: bytes, from: from)
            case .set(let set): unsafe ByteScan.firstIndex(ofAnyNeedles: needles, bytes: set, in: bytes, from: from)
        }
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
