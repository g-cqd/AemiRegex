import Synchronization

/// Everything one search mutates: the DFA caches and the Pike VM buffers. A pattern keeps a few of these in a pool, so concurrent
/// searches never share one and repeated searches reuse the states already built.
struct SearchScratch {
    var forward: LazyDFA?
    var reverse: LazyDFA?
    var pike: PikeVM
}

/// A bounded-by-concurrency stack of scratch values. Taking and returning one is a short lock; a search holds none while it runs.
final class ScratchPool: Sendable {
    private let free = Mutex<[SearchScratch]>([])
    private let make: @Sendable () -> SearchScratch

    init(make: @escaping @Sendable () -> SearchScratch) { self.make = make }

    /// Runs `body` with exclusive use of a scratch value, then returns it to the pool.
    func withScratch<Result>(_ body: (inout SearchScratch) -> Result) -> Result {
        var scratch = free.withLock { $0.popLast() } ?? make()
        defer { free.withLock { $0.append(scratch) } }
        return body(&scratch)
    }
}
