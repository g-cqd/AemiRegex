/// A scratch value in a reference, so the pool moves a pointer instead of copying about thirty arrays on every search.
///
/// `@unchecked Sendable` is sound under one rule: a box is in the pool or in exactly one search, never both. The pool hands it out
/// under its lock and takes it back under its lock, and the concurrency test (many tasks on one pattern) checks the rule.
final class ScratchBox: @unchecked Sendable {
    var value: SearchScratch

    init(_ value: SearchScratch) { self.value = value }
}
