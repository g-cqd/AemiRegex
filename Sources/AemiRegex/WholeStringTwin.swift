internal import Synchronization

/// The whole-string program of a pattern compiled for search, built the first time ``Pattern/wholeMatch(in:)`` asks for it.
///
/// A whole match is the highest-priority match that spans the text. The search program's leftmost-first match may stop short where a
/// lower-priority path reaches the end (`a|ab` on `ab`), so the whole match runs a program that itself requires both edges, as
/// ``Pattern/Matching/wholeString`` compiles. Copies of a pattern share the box, so the program is compiled once, and reading it after
/// that takes no lock.
final class WholeStringTwin: @unchecked Sendable {
    private final class Compiled: Sendable {
        let pattern: Pattern

        init(_ pattern: Pattern) { self.pattern = pattern }

        func firstMatch<S: StringProtocol>(in text: S) -> Match? { pattern.firstMatch(in: text) }
    }

    private enum State: UInt8, AtomicRepresentable {
        case pending
        case compiled
        /// The whole-string program is over a limit the search program was under: it is two instructions longer.
        case overLimit
    }

    private let source: String
    private let limits: Pattern.Limits
    private let engine: Pattern.Engine
    // Double-checked publication rather than `AtomicLazyReference`, whose `load()` is not specialized into this module and looked up
    // generic metadata on every call. `compiled` is written once, under `lock`, before `state` leaves `pending` with release ordering;
    // a reader that loads `compiled` or `overLimit` with acquire ordering sees that write, and nothing writes it again. That is the
    // whole of the `@unchecked Sendable`.
    private let state = Atomic<State>(.pending)
    private let lock = Mutex<Void>(())
    private nonisolated(unsafe) var compiled: Compiled?

    init(source: String, limits: Pattern.Limits, engine: Pattern.Engine) {
        self.source = source
        self.limits = limits
        self.engine = engine
    }

    /// The whole match of `text`: the whole-string program's match, compiled on first use.
    ///
    /// When that program is over a limit, the leftmost-first match of `search`, kept when it spans, is the best left.
    func wholeMatch<S: StringProtocol>(in text: S, searching search: borrowing Pattern) -> Match? {
        var current = state.load(ordering: .acquiring)
        if current == .pending { current = compile() }
        if current == .compiled, let compiled = unsafe compiled {
            return compiled.firstMatch(in: text)
        }
        guard let match = search.firstMatch(in: text), match.range == 0 ..< text.utf8.count else { return nil }
        return match
    }

    /// Compiles the program and publishes it, once; a task that loses the race waits for the winner's.
    @inline(never)
    private func compile() -> State {
        lock.withLock { _ in
            let current = state.load(ordering: .acquiring)
            guard current == .pending else { return current }
            let published: State
            if let pattern = try? Pattern(source, source: source, limits: limits, engine: engine, wholeString: true) {
                unsafe compiled = Compiled(pattern)
                published = .compiled
            } else {
                published = .overLimit
            }
            state.store(published, ordering: .releasing)
            return published
        }
    }
}
