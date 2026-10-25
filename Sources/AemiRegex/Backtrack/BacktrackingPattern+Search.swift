/// Searching more than once, and searching a `String` or `Substring`. Each call has one ``BacktrackingPattern/Budget``, shared by every search inside it.
extension BacktrackingPattern {
    /// Runs `body` with a machine over `buffer`; a budget error comes back as a value because the standard library's `with…` calls cannot
    /// carry a typed error.
    private func run<Value>(
        _ buffer: UnsafeBufferPointer<UInt8>, _ body: (inout BTMachine, ByteBuffer) throws(BacktrackError) -> Value
    ) -> Result<Value, BacktrackError> {
        var machine = BTMachine(program, budget: budget)
        do throws(BacktrackError) {
            return .success(try body(&machine, unsafe ByteBuffer(buffer)))
        } catch {
            return .failure(error)
        }
    }

    func search<Value>(
        _ haystack: [UInt8], _ body: (inout BTMachine, ByteBuffer) throws(BacktrackError) -> Value
    ) throws(BacktrackError) -> Value {
        try (haystack.withUnsafeBufferPointer { unsafe run($0, body) }).get()
    }

    /// As ``search(_:_:)`` over a string's or substring's UTF-8: read in place when stored contiguously, copied once when not.
    func search<S: StringProtocol, Value>(
        in text: S, _ body: (inout BTMachine, ByteBuffer) throws(BacktrackError) -> Value
    ) throws(BacktrackError) -> Value {
        if let outcome = text.utf8.withContiguousStorageIfAvailable({ unsafe run($0, body) }) {
            return try outcome.get()
        }
        return try search(Array(text.utf8), body)
    }

    /// Every match, left to right.
    ///
    /// After an empty match ECMAScript moves one scalar on, as `matchAll` does; PCRE2 first looks for a non-empty match at the same place,
    /// as `pcre2test`'s `g` does. An empty match may touch the previous match, unlike in ``Pattern/matches(in:)-([UInt8])``.
    /// - Parameter haystack: The bytes to search.
    /// - Returns: The matches in order; empty when there are none.
    /// - Throws: ``BacktrackError/budgetExceeded(_:)`` when the whole call uses up its ``Budget``.
    /// - Complexity: Exponential in the worst case, bounded by ``Budget/maxSteps`` for the call as a whole.
    public func matches(in haystack: [UInt8]) throws(BacktrackError) -> [Match] {
        try search(haystack) { machine, bytes throws(BacktrackError) in try machine.allMatches(in: bytes) }
    }

    /// Whether there is a match anywhere in `haystack`.
    /// - Throws: ``BacktrackError/budgetExceeded(_:)`` when the search uses up its ``Budget``.
    public func isMatch(in haystack: [UInt8]) throws(BacktrackError) -> Bool { try firstMatch(in: haystack) != nil }

    /// The leftmost match in `text` that starts at or after `start` (the start of the text when `nil`).
    ///
    /// - Parameters:
    ///   - text: The text to search (`String` or `Substring`).
    ///   - start: An index of `text`.
    /// - Returns: The match, or `nil`. Use ``Match/range(in:)`` for `String.Index` ranges.
    /// - Throws: ``BacktrackError/budgetExceeded(_:)`` when the search uses up its ``Budget``.
    public func firstMatch<S: StringProtocol>(in text: S, from start: S.Index? = nil) throws(BacktrackError) -> Match? {
        let offset = start.map { text.utf8.distance(from: text.utf8.startIndex, to: $0) } ?? 0
        return try search(in: text) { machine, bytes throws(BacktrackError) in
            try machine.firstMatch(in: bytes, from: offset)
        }
    }

    /// Every match in `text`, left to right (see ``matches(in:)-([UInt8])``).
    /// - Throws: ``BacktrackError/budgetExceeded(_:)`` when the call uses up its ``Budget``.
    public func matches<S: StringProtocol>(in text: S) throws(BacktrackError) -> [Match] {
        try search(in: text) { machine, bytes throws(BacktrackError) in try machine.allMatches(in: bytes) }
    }

    /// Whether there is a match anywhere in `text`.
    /// - Throws: ``BacktrackError/budgetExceeded(_:)`` when the search uses up its ``Budget``.
    public func isMatch<S: StringProtocol>(in text: S) throws(BacktrackError) -> Bool {
        try firstMatch(in: text) != nil
    }
}
