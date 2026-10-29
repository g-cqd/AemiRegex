internal import AemiKernel

/// The threads alive at one input position, in priority order, with each thread's capture slots.
struct ThreadList {
    var set: SparseSet
    /// `slotCount` entries per program counter; only the rows of threads in `set` are meaningful.
    var slots: [Int]

    init(instructionCount: Int, slotCount: Int) {
        set = SparseSet(capacity: instructionCount)
        slots = [Int](repeating: -1, count: instructionCount * slotCount)
    }
}
