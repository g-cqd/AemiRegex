// @dl:disable exact-clone -- parallel surface across Pattern and BacktrackingPattern
/// Convenient search, replacement and splitting operations on any `StringProtocol`.
extension BacktrackingPattern {
    /// The highest-priority match that spans all of `text`, as Swift `Regex.wholeMatch` defines it.
    ///
    /// The search starts only at the beginning, and a path that reaches the end of the pattern anywhere else backtracks into the next
    /// alternative, so `a|ab` matches all of `ab`.
    public func wholeMatch<S: StringProtocol>(in text: S) throws(BacktrackError) -> Match? {
        try search(in: text) { machine, bytes throws(BacktrackError) in try machine.wholeMatch(in: bytes) }
    }

    /// The highest-priority match that starts at the beginning of `text`; only that start is tried.
    public func prefixMatch<S: StringProtocol>(in text: S) throws(BacktrackError) -> Match? {
        try search(in: text) { machine, bytes throws(BacktrackError) in
            try machine.firstMatch(in: bytes, from: 0, anchored: true)
        }
    }

    /// Returns a new string with the first non-overlapping match replaced with `replacement`.
    public func replacingFirstMatch<S: StringProtocol>(
        in text: S, with replacement: String
    ) throws(BacktrackError) -> String {
        try replacingFirstMatch(in: text) { _ in replacement }
    }

    /// Returns a new string with every non-overlapping match replaced with `replacement`.
    public func replacingMatches<S: StringProtocol>(
        in text: S, with replacement: String
    ) throws(BacktrackError) -> String {
        try replacingMatches(in: text) { _ in replacement }
    }

    /// Returns a new string with the first match replaced with the string returned by `transform`.
    public func replacingFirstMatch<S: StringProtocol>(
        in text: S, using transform: (Match) throws(BacktrackError) -> String
    ) throws(BacktrackError) -> String {
        guard let match = try firstMatch(in: text) else { return String(text) }
        let matchRange = match.range(in: text)
        var result = ""
        result.reserveCapacity(text.utf8.count)
        result.append(contentsOf: text[..<matchRange.lowerBound])
        result.append(try transform(match))
        result.append(contentsOf: text[matchRange.upperBound...])
        return result
    }

    /// Returns a new string with every non-overlapping match replaced with the string returned by `transform`.
    public func replacingMatches<S: StringProtocol>(
        in text: S, using transform: (Match) throws(BacktrackError) -> String
    ) throws(BacktrackError) -> String {
        let all = try matches(in: text)
        guard !all.isEmpty else { return String(text) }
        var result = ""
        result.reserveCapacity(text.utf8.count)
        var cursor = text.startIndex
        for match in all {
            let matchRange = match.range(in: text)
            if matchRange.lowerBound > cursor {
                result.append(contentsOf: text[cursor ..< matchRange.lowerBound])
            }
            result.append(try transform(match))
            cursor = matchRange.upperBound
        }
        if cursor < text.endIndex {
            result.append(contentsOf: text[cursor...])
        }
        return result
    }

    /// Splits `text` around matches of this pattern.
    public func split<S: StringProtocol>(
        in text: S, maxSplits: Int = Int.max, omittingEmptySubsequences: Bool = false
    ) throws(BacktrackError) -> [Substring] {
        guard maxSplits >= 0 else { return [Substring(text[...])] }
        let all = try matches(in: text)
        var result: [Substring] = []
        var cursor = text.startIndex
        var splitsDone = 0

        for match in all {
            if splitsDone >= maxSplits { break }
            let r = match.range(in: text)
            let piece = text[cursor ..< r.lowerBound]
            if !omittingEmptySubsequences || !piece.isEmpty {
                result.append(Substring(piece))
                splitsDone += 1
            }
            cursor = r.upperBound
        }

        let remaining = text[cursor...]
        if !omittingEmptySubsequences || !remaining.isEmpty {
            result.append(Substring(remaining))
        }
        return result
    }
}

// @dl:enable exact-clone
