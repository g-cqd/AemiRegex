import Synchronization

/// Everything one search mutates: the DFA caches and the Pike VM buffers. A pattern keeps a few of these in a pool, so concurrent
/// searches never share one and repeated searches reuse the states already built.
struct SearchScratch {
    var forward: LazyDFA?
    var reverse: LazyDFA?
    var pike: PikeVM
}

/// A scratch value in a reference, so the pool moves a pointer instead of copying about thirty arrays on every search.
///
/// `@unchecked Sendable` is sound under one rule: a box is in the pool or in exactly one search, never both. The pool hands it out
/// under its lock and takes it back under its lock, and the concurrency test (many tasks on one pattern) checks the rule.
final class ScratchBox: @unchecked Sendable {
    var value: SearchScratch

    init(_ value: SearchScratch) { self.value = value }
}

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
