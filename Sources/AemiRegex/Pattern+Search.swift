extension Pattern {
    /// The leftmost match at or after `start` in a borrowed buffer, or `nil` (and `nil` for a `start` outside it).
    func firstMatch(inBuffer buffer: ByteBuffer, from start: Int) -> Match? {
        guard start >= 0, start <= buffer.count else { return nil }
        var allowDFA = true
        return pool.withScratch { search(&$0, buffer, from: start, allowDFA: &allowDFA) }
    }

    /// Calls `body` with each match in a borrowed buffer, left to right; `body` returns `false` to stop. An empty match that touches the
    /// previous one is skipped and the position advances one scalar, as in RE2 and Go.
    func forEachMatch(inBuffer buffer: ByteBuffer, _ body: (Match) -> Bool) {
        pool.withScratch { scratch in
            var position = 0
            var previousEnd = -1
            var allowDFA = true
            while position <= buffer.count, let match = search(&scratch, buffer, from: position, allowDFA: &allowDFA) {
                var accept = true
                if match.range.upperBound == position {
                    if match.range.lowerBound == previousEnd { accept = false }
                    position += position < buffer.count ? Utf8.width(of: buffer, at: position) : 1
                } else {
                    position = match.range.upperBound
                }
                previousEnd = match.range.upperBound
                if accept, !body(match) { return }
            }
        }
    }

    // MARK: Search

    /// One search: the DFA finds where the match ends and where it starts, and the Pike VM runs on that window only if the
    /// pattern has captures. A DFA that gives up (cache full) disables itself for the rest of the call and the Pike VM answers.
    ///
    /// The DFA starts a match at every byte, the Pike VM only at scalar boundaries. A match that begins with a byte cannot start
    /// inside a scalar, so the two differ only for an empty match inside one; such a match is dropped and the search resumes at the
    /// next byte, which is what the Pike VM would have done (at most three retries per scalar).
    func search(_ scratch: inout SearchScratch, _ haystack: ByteBuffer, from start: Int, allowDFA: inout Bool)
        -> Match?
    {
        if let literals {
            scratch.counts.literal += 1
            return literalSearch(literals, haystack, from: start)
        }
        if endAnchored, allowDFA, scratch.reverse != nil {
            scratch.counts.endAnchored += 1
            var gaveUp = false
            let end = haystack.count
            let begin = unsafe scratch.reverse?.searchReverse(haystack.buffer, end: end, floor: start, gaveUp: &gaveUp)
            guard gaveUp else {
                guard let matchStart = begin ?? nil else { return nil }
                if program.captureCount == 0 { return Match(range: matchStart ..< end) }
                return pike(&scratch, haystack, from: matchStart, anchored: true, limit: end)
            }
            scratch.reverse?.reset()
            allowDFA = false
        }
        if allowDFA, scratch.forward != nil {
            scratch.counts.dfa += 1
            var from = start
            while from <= haystack.count {
                let outcome = unsafe scratch.forward?.searchForward(haystack.buffer, from: from, prefilter: prefilter)
                guard case .match(let end) = outcome else {
                    if outcome == .noMatch { return nil }
                    scratch.forward?.reset()
                    break
                }
                var gaveUp = false
                let matchStart = unsafe scratch.reverse?
                    .searchReverse(haystack.buffer, end: end, floor: from, gaveUp: &gaveUp)
                guard let matchStart else {
                    if gaveUp { scratch.reverse?.reset() }
                    break
                }
                if matchStart == end, !PikeVM.isBoundary(haystack, matchStart) {
                    from = matchStart + 1
                    continue
                }
                if program.captureCount == 0 { return Match(range: matchStart ..< end) }
                return pike(&scratch, haystack, from: matchStart, anchored: true, limit: end)
            }
            if from > haystack.count { return nil }
            allowDFA = false
        }
        return pike(&scratch, haystack, from: start, anchored: false, limit: nil)
    }

    /// The leftmost match of a pure literal alternation: the prefilter offers candidates and the alternatives are checked at each.
    func literalSearch(_ literals: LiteralSet, _ haystack: ByteBuffer, from start: Int) -> Match? {
        unsafe literals.firstMatch(in: haystack.buffer, from: start, prefilter: prefilter).map { Match(range: $0) }
    }

    func pike(_ scratch: inout SearchScratch, _ haystack: ByteBuffer, from start: Int, anchored: Bool, limit: Int?)
        -> Match?
    {
        scratch.counts.pike += 1
        guard scratch.pike.search(haystack, from: start, anchored: anchored, limit: limit) else { return nil }
        let slots = scratch.pike.best
        let captures = (1 ..< slots.count / 2)
            .map { group -> Range<Int>? in
                let lower = slots[2 * group]
                let upper = slots[2 * group + 1]
                return lower >= 0 && upper >= lower ? lower ..< upper : nil
            }
        return Match(range: slots[0] ..< slots[1], captures: captures)
    }
}
