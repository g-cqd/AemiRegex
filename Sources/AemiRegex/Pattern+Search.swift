extension Pattern {
    /// The leftmost match at or after `start` in a borrowed buffer, or `nil` (and `nil` for a `start` outside it).
    ///
    /// With `needsCaptures` false the match carries only its range, and a pattern with capture groups does not run the Pike VM to fill them in.
    func firstMatch(inBuffer buffer: ByteBuffer, from start: Int, needsCaptures: Bool = true) -> Match? {
        guard start >= 0, start <= buffer.count else { return nil }
        var allowDFA = true
        return pool.withScratch { search(&$0, buffer, from: start, needsCaptures: needsCaptures, allowDFA: &allowDFA) }
    }

    /// Calls `body` with each match in a borrowed buffer, left to right; `body` returns `false` to stop. An empty match that touches the
    /// previous one is skipped and the position advances one scalar, as in RE2 and Go.
    func forEachMatch(inBuffer buffer: ByteBuffer, needsCaptures: Bool = true, _ body: (Match) -> Bool) {
        pool.withScratch { scratch in
            var position = 0
            var previousEnd = -1
            var allowDFA = true
            while position <= buffer.count,
                let match = search(
                    &scratch, buffer, from: position, needsCaptures: needsCaptures, allowDFA: &allowDFA)
            {
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
    func search(
        _ scratch: inout SearchScratch, _ haystack: ByteBuffer, from start: Int, needsCaptures: Bool,
        allowDFA: inout Bool
    ) -> Match? {
        if let literals {
            scratch.counts.literal += 1
            return literalSearch(literals, haystack, from: start)
        }
        if allowDFA {
            let attempt = searchWithDFAs(&scratch, haystack, from: start, needsCaptures: needsCaptures)
            if case .answer(let match) = attempt { return match }
            allowDFA = false
        }
        return pike(&scratch, haystack, from: start, anchored: false, limit: nil, needsCaptures: needsCaptures)
    }

    /// The first strategy that applies decides: backwards from the end, between terminal bytes, or forwards. `.gaveUp` means a DFA's
    /// cache filled up (it is reset) or no DFA exists, so the Pike VM must answer.
    private func searchWithDFAs(
        _ scratch: inout SearchScratch, _ haystack: ByteBuffer, from start: Int, needsCaptures: Bool
    ) -> SearchAttempt {
        if endAnchored, scratch.reverse != nil {
            scratch.counts.endAnchored += 1
            return searchBackwards(&scratch, haystack, from: start, needsCaptures: needsCaptures)
        }
        if jumpsToTerminalByte, let terminalByte, scratch.reverse != nil {
            scratch.counts.terminal += 1
            return searchBetween(terminalByte, &scratch, haystack, from: start, needsCaptures: needsCaptures)
        }
        guard scratch.forward != nil else { return .gaveUp }
        scratch.counts.dfa += 1
        return searchForwards(&scratch, haystack, from: start, needsCaptures: needsCaptures)
    }

    /// Every match ends at the end of the text, so the reverse DFA runs from there and finds the leftmost start.
    private func searchBackwards(
        _ scratch: inout SearchScratch, _ haystack: ByteBuffer, from start: Int, needsCaptures: Bool
    ) -> SearchAttempt {
        var gaveUp = false
        let end = haystack.count
        let begin = unsafe scratch.reverse?.searchReverse(haystack.buffer, end: end, floor: start, gaveUp: &gaveUp)
        guard !gaveUp else {
            scratch.reverse?.reset()
            return .gaveUp
        }
        guard let matchStart = begin ?? nil else { return .answer(nil) }
        return .answer(complete(&scratch, haystack, start: matchStart, end: end, needsCaptures: needsCaptures))
    }

    /// Jumps between occurrences of the terminal byte (see ``TerminalByte``): the first one that ends a match ends the leftmost match,
    /// and its start is the farthest the reverse DFA reaches back, down to `start`.
    private func searchBetween(
        _ byte: UInt8, _ scratch: inout SearchScratch, _ haystack: ByteBuffer, from start: Int, needsCaptures: Bool
    ) -> SearchAttempt {
        var from = start
        while from < haystack.count {
            guard let found = unsafe ByteScan.firstIndex(of: byte, in: haystack.buffer, from: from) else {
                return .answer(nil)
            }
            var gaveUp = false
            let begin = unsafe scratch.reverse?
                .searchReverse(haystack.buffer, end: found + 1, floor: from, gaveUp: &gaveUp)
            guard !gaveUp else {
                scratch.reverse?.reset()
                return .gaveUp
            }
            if let matchStart = begin ?? nil {
                return .answer(
                    complete(&scratch, haystack, start: matchStart, end: found + 1, needsCaptures: needsCaptures))
            }
            from = found + 1
        }
        return .answer(nil)
    }

    /// The forward DFA finds where the match ends, the reverse DFA where it starts.
    private func searchForwards(
        _ scratch: inout SearchScratch, _ haystack: ByteBuffer, from start: Int, needsCaptures: Bool
    ) -> SearchAttempt {
        var from = start
        while from <= haystack.count {
            let outcome = unsafe scratch.forward?.searchForward(haystack.buffer, from: from, prefilter: prefilter)
            guard case .match(let end) = outcome else {
                if outcome == .noMatch { return .answer(nil) }
                scratch.forward?.reset()
                return .gaveUp
            }
            var gaveUp = false
            let matchStart = unsafe scratch.reverse?
                .searchReverse(haystack.buffer, end: end, floor: from, gaveUp: &gaveUp)
            guard let matchStart else {
                if gaveUp { scratch.reverse?.reset() }
                return .gaveUp
            }
            if matchStart == end, !PikeVM.isBoundary(haystack, matchStart) {
                from = matchStart + 1
                continue
            }
            return .answer(complete(&scratch, haystack, start: matchStart, end: end, needsCaptures: needsCaptures))
        }
        return .answer(nil)
    }

    /// The match `start ..< end` the DFAs found, with its capture groups when asked for and the pattern has any.
    private func complete(
        _ scratch: inout SearchScratch, _ haystack: ByteBuffer, start: Int, end: Int, needsCaptures: Bool
    ) -> Match? {
        if program.captureCount == 0 || !needsCaptures { return Match(range: start ..< end) }
        return pike(&scratch, haystack, from: start, anchored: true, limit: end, needsCaptures: true)
    }

    /// The leftmost match of a pure literal alternation: the prefilter offers candidates and the alternatives are checked at each.
    func literalSearch(_ literals: LiteralSet, _ haystack: ByteBuffer, from start: Int) -> Match? {
        unsafe literals.firstMatch(in: haystack.buffer, from: start, prefilter: prefilter).map { Match(range: $0) }
    }

    func pike(
        _ scratch: inout SearchScratch, _ haystack: ByteBuffer, from start: Int, anchored: Bool, limit: Int?,
        needsCaptures: Bool
    ) -> Match? {
        scratch.counts.pike += 1
        guard scratch.pike.search(haystack, from: start, anchored: anchored, limit: limit) else { return nil }
        let slots = scratch.pike.best
        guard needsCaptures else { return Match(range: slots[0] ..< slots[1]) }
        let captures = (1 ..< slots.count / 2)
            .map { group -> Range<Int>? in
                let lower = slots[2 * group]
                let upper = slots[2 * group + 1]
                return lower >= 0 && upper >= lower ? lower ..< upper : nil
            }
        return Match(range: slots[0] ..< slots[1], captures: captures)
    }
}
