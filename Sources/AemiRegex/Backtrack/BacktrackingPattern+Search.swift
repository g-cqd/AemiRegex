/// Searching more than once, and searching a `String`. Each call has one ``BacktrackingPattern/Budget``, shared by every search inside it.
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

    /// As ``search(_:_:)`` over a string's UTF-8: read in place when the string stores it contiguously, copied once when not.
    func search<Value>(
        string: String, _ body: (inout BTMachine, ByteBuffer) throws(BacktrackError) -> Value
    ) throws(BacktrackError) -> Value {
        if let outcome = string.utf8.withContiguousStorageIfAvailable({ unsafe run($0, body) }) {
            return try outcome.get()
        }
        return try search(Array(string.utf8), body)
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

    /// The leftmost match in `string` that starts at or after `start` (the start of the string when `nil`).
    ///
    /// - Parameters:
    ///   - string: The text to search.
    ///   - start: An index of `string`.
    /// - Returns: The match, or `nil`. Use ``Match/range(in:)`` for `String.Index` ranges.
    /// - Throws: ``BacktrackError/budgetExceeded(_:)`` when the search uses up its ``Budget``.
    public func firstMatch(in string: String, from start: String.Index? = nil) throws(BacktrackError) -> Match? {
        let offset = start.map { string.utf8.distance(from: string.utf8.startIndex, to: $0) } ?? 0
        return try search(string: string) { machine, bytes throws(BacktrackError) in
            try machine.firstMatch(in: bytes, from: offset)
        }
    }

    /// Every match in `string`, left to right (see ``matches(in:)-([UInt8])``).
    /// - Throws: ``BacktrackError/budgetExceeded(_:)`` when the call uses up its ``Budget``.
    public func matches(in string: String) throws(BacktrackError) -> [Match] {
        try search(string: string) { machine, bytes throws(BacktrackError) in try machine.allMatches(in: bytes) }
    }

    /// Whether there is a match anywhere in `string`.
    /// - Throws: ``BacktrackError/budgetExceeded(_:)`` when the search uses up its ``Budget``.
    public func isMatch(in string: String) throws(BacktrackError) -> Bool { try firstMatch(in: string) != nil }
}
