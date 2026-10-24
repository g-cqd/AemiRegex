/// The first two bytes of a possible match.
struct BytePair: Hashable, Comparable, Sendable {
    let first: UInt8
    let second: UInt8

    init(_ first: UInt8, _ second: UInt8) {
        self.first = first
        self.second = second
    }

    static func < (lhs: BytePair, rhs: BytePair) -> Bool {
        (lhs.first, lhs.second) < (rhs.first, rhs.second)
    }
}
