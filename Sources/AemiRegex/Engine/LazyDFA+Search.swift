extension LazyDFA {
    // MARK: Searching

    /// Finds the end of the leftmost-first match that starts at or after `from`.
    /// - Complexity: O(haystack size) once the states are cached; each new state costs O(program size).
    mutating func searchForward(_ haystack: UnsafeBufferPointer<UInt8>, from: Int, prefilter: Prefilter) -> Outcome {
        let count = haystack.count
        var position = from
        var state = startStates[unsafe previousContext(haystack, at: position)]
        var lastEnd = -1
        while true {
            if flags[Int(state)] & Flag.start != 0 {
                guard let candidate = unsafe prefilter.next(in: haystack, from: position) else { break }
                if candidate != position {
                    position = candidate
                    state = startStates[unsafe previousContext(haystack, at: position)]
                }
            }
            guard position < count else { break }
            var byteClass = Int(classes.map[Int(unsafe haystack[position])])
            var next = table[Int(state) << strideShift + byteClass]
            if next & Self.tagMask == 0 {
                // Plain transitions in a row: leave the checked path. When the first one is already tagged (a match every few
                // bytes) the loop's setup would be wasted, which is why one step is taken before it.
                let (stopped, row) = unsafe scanForward(haystack, from: position, state: state)
                position = stopped
                state = row
                guard position < count else { break }
                byteClass = Int(classes.map[Int(unsafe haystack[position])])
                next = table[Int(state) << strideShift + byteClass]
            }
            if next < 0 {
                guard let built = transition(from: state, byteClass: byteClass) else { return .gaveUp }
                next = built
            }
            state = (next & Self.offsetMask) >> Int32(strideShift)
            position += 1
            let flag = flags[Int(state)]
            if flag & Flag.match != 0 { lastEnd = position - 1 }
            if flag & Flag.dead != 0 { return lastEnd >= 0 ? .match(lastEnd) : .noMatch }
        }
        if position >= count, finalMatch(state, next: NeighborContext.edge) { lastEnd = count }
        return lastEnd >= 0 ? .match(lastEnd) : .noMatch
    }

    /// Finds the smallest start `>= floor` of a match that ends exactly at `end`, scanning backwards over the reversed program.
    /// - Returns: The start, or `nil` when no match ends there. `gaveUp` is set when the cache limit stopped the scan.
    mutating func searchReverse(
        _ haystack: UnsafeBufferPointer<UInt8>, end: Int, floor: Int, gaveUp: inout Bool
    ) -> Int? {
        var position = end
        var state = startStates[end == haystack.count ? NeighborContext.edge : contextOf(unsafe haystack[end])]
        var best: Int?
        while position > floor {
            var byteClass = Int(classes.map[Int(unsafe haystack[position - 1])])
            var next = table[Int(state) << strideShift + byteClass]
            if next & Self.tagMask == 0 {
                let (stopped, row) = unsafe scanBackward(haystack, from: position, floor: floor, state: state)
                position = stopped
                state = row
                guard position > floor else { break }
                byteClass = Int(classes.map[Int(unsafe haystack[position - 1])])
                next = table[Int(state) << strideShift + byteClass]
            }
            if next < 0 {
                guard let built = transition(from: state, byteClass: byteClass) else {
                    gaveUp = true
                    return nil
                }
                next = built
            }
            let nextState = (next & Self.offsetMask) >> Int32(strideShift)
            if flags[Int(nextState)] & Flag.match != 0 { best = position }
            state = nextState
            position -= 1
            if flags[Int(state)] & Flag.dead != 0 { return best }
        }
        let after = floor == 0 ? NeighborContext.edge : contextOf(unsafe haystack[floor - 1])
        if finalMatch(state, next: after) { best = floor }
        return best
    }

    // MARK: The hot loops

    /// Follows built, untagged transitions forward from `position` until the next one is tagged, unbuilt, or the text ends.
    /// - Returns: The position of the byte whose transition needs the slow path, and the state it is taken from.
    ///
    /// Memory safety: this is the only unchecked indexing in the DFA. Reads are `haystack[p]` with `p < haystack.count` (the loop
    /// guard), `classMap[byte]` with `classMap.count == 256`, and `table[row + class]` where `row` is an offset this DFA wrote
    /// (a multiple of the stride below `table.count`) and `class < classes.count <= stride`. An untagged entry is by construction
    /// the offset of a built row, and `table` is not mutated while this runs. Tests: golden, generated and agreement suites
    /// (every transition), and the sanitizer runs.
    private func scanForward(_ haystack: UnsafeBufferPointer<UInt8>, from: Int, state: Int32) -> (Int, Int32) {
        let count = haystack.count
        let shift = strideShift
        return table.withUnsafeBufferPointer { table in
            classes.map.withUnsafeBufferPointer { classMap in
                assert(classMap.count == 256 && from >= 0 && from <= count)
                var row = Int(state) << shift
                var position = from
                while position < count {
                    let next = unsafe table[row + Int(unsafe classMap[Int(unsafe haystack[position])])]
                    if next & Self.tagMask != 0 { break }
                    row = Int(next)
                    assert(row >= 0 && row + (1 << shift) <= table.count, "an untagged entry must be a built row")
                    position += 1
                }
                return (position, Int32(row >> shift))
            }
        }
    }

    /// The backward twin of ``scanForward(_:from:state:)``: reads `haystack[position - 1]` while `position > floor`.
    private func scanBackward(_ haystack: UnsafeBufferPointer<UInt8>, from: Int, floor: Int, state: Int32) -> (
        Int, Int32
    ) {
        let shift = strideShift
        return table.withUnsafeBufferPointer { table in
            classes.map.withUnsafeBufferPointer { classMap in
                assert(classMap.count == 256 && floor >= 0 && from <= haystack.count)
                var row = Int(state) << shift
                var position = from
                while position > floor {
                    let next = unsafe table[row + Int(unsafe classMap[Int(unsafe haystack[position - 1])])]
                    if next & Self.tagMask != 0 { break }
                    row = Int(next)
                    assert(row >= 0 && row + (1 << shift) <= table.count, "an untagged entry must be a built row")
                    position -= 1
                }
                return (position, Int32(row >> shift))
            }
        }
    }

    private func previousContext(_ haystack: UnsafeBufferPointer<UInt8>, at position: Int) -> Int {
        guard usesContext, position > 0, position <= haystack.count else { return 0 }
        return contextOf(unsafe haystack[position - 1])
    }

    private func contextOf(_ byte: UInt8) -> Int { usesContext ? NeighborContext.of(byte) : 0 }
}
