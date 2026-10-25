import Synchronization

/// A bounded-by-concurrency stack of scratch boxes. Taking and returning one is a short lock; a search holds none while it runs.
final class ScratchPool: Sendable {
    private let free = Mutex<[ScratchBox]>([])
    private let make: @Sendable () -> SearchScratch

    init(make: @escaping @Sendable () -> SearchScratch) { self.make = make }

    /// Runs `body` with exclusive use of a scratch value, then returns it to the pool.
    func withScratch<Result>(_ body: (inout SearchScratch) -> Result) -> Result {
        let box = free.withLock { $0.popLast() } ?? ScratchBox(make())
        defer { free.withLock { $0.append(box) } }
        return body(&box.value)
    }
}
