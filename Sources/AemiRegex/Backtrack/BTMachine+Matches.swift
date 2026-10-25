extension BTMachine {
    /// Every match, left to right, as ECMAScript's `matchAll` and PCRE2's global matching list them.
    ///
    /// After an empty match ECMAScript moves one scalar on; PCRE2 first looks for a non-empty match at the same place, then moves on.
    /// An empty match may touch the previous match, unlike in ``Pattern``.
    /// - Throws: ``BacktrackError`` when the budget, shared by every search here, runs out.
    mutating func allMatches(in bytes: ByteBuffer) throws(BacktrackError) -> [Match] {
        var result: [Match] = []
        var from = 0
        var retryNonEmpty = false
        while from <= bytes.count {
            let found: Match?
            if retryNonEmpty {
                found = try firstMatch(in: bytes, from: from, anchored: true, nonEmptyAtStart: true)
                if found == nil {
                    guard from < bytes.count else { break }
                    from += ScalarReader.step(in: bytes, at: from)
                    retryNonEmpty = false
                    continue
                }
            } else {
                found = try firstMatch(in: bytes, from: from)
            }
            guard let match = found else { break }
            result.append(match)
            from = match.range.upperBound
            retryNonEmpty = false
            guard match.range.isEmpty else { continue }
            if program.dialect == .pcre2 {
                retryNonEmpty = true
            } else {
                guard from < bytes.count else { break }
                from += ScalarReader.step(in: bytes, at: from)
            }
        }
        return result
    }
}
