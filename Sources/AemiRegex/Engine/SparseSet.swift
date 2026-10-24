/// A set of small integers with O(1) insert, membership and clear, and iteration in insertion order.
struct SparseSet {
    private(set) var dense: [Int32]
    private var sparse: [Int32]
    private(set) var count = 0

    init(capacity: Int) {
        dense = [Int32](repeating: 0, count: capacity)
        sparse = [Int32](repeating: 0, count: capacity)
    }

    var isEmpty: Bool { count == 0 }

    func contains(_ value: Int) -> Bool {
        let slot = Int(sparse[value])
        return slot < count && Int(dense[slot]) == value
    }

    /// Adds `value`; the caller has checked ``contains(_:)``.
    mutating func insert(_ value: Int) {
        dense[count] = Int32(truncatingIfNeeded: value)
        sparse[value] = Int32(truncatingIfNeeded: count)
        count += 1
    }

    mutating func removeAll() { count = 0 }
}
