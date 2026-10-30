/// Convenient search, replacement and splitting operations on any `StringProtocol`.
extension Pattern {
    /// The highest-priority match that spans all of `text`, as Swift `Regex.wholeMatch` and RE2's `FullMatch` define it.
    ///
    /// This is not the leftmost-first match kept when it happens to span: `a|ab` matches all of `ab`. The first call compiles a
    /// whole-string program from the same source, shared by copies of the pattern; a pattern compiled with
    /// ``Matching/wholeString`` already is one.
    public func wholeMatch<S: StringProtocol>(in text: S) -> Match? {
        guard let twin = wholeStringTwin else { return firstMatch(in: text) }
        return twin.wholeMatch(in: text, searching: self)
    }

    /// Matches `text` only if the match starts at the beginning of `text`.
    public func prefixMatch<S: StringProtocol>(in text: S) -> Match? {
        guard let match = firstMatch(in: text, from: text.startIndex),
            match.range.lowerBound == 0
        else { return nil }
        return match
    }

    /// Returns a new string with the first non-overlapping match replaced with `replacement`.
    public func replacingFirstMatch<S: StringProtocol>(in text: S, with replacement: String) -> String {
        replacingFirstMatch(in: text) { _ in replacement }
    }

    /// Returns a new string with every non-overlapping match replaced with `replacement`.
    public func replacingMatches<S: StringProtocol>(in text: S, with replacement: String) -> String {
        replacingMatches(in: text) { _ in replacement }
    }

    /// Returns a new string with the first match replaced with the string returned by `transform`.
    public func replacingFirstMatch<S: StringProtocol>(in text: S, using transform: (Match) -> String) -> String {
        guard let match = firstMatch(in: text) else { return String(text) }
        let matchRange = match.range(in: text)
        var result = ""
        result.reserveCapacity(text.utf8.count)
        result.append(contentsOf: text[..<matchRange.lowerBound])
        result.append(transform(match))
        result.append(contentsOf: text[matchRange.upperBound...])
        return result
    }

    /// Returns a new string with every non-overlapping match replaced with the string returned by `transform`.
    public func replacingMatches<S: StringProtocol>(in text: S, using transform: (Match) -> String) -> String {
        let all = matches(in: text)
        guard !all.isEmpty else { return String(text) }
        var result = ""
        result.reserveCapacity(text.utf8.count)
        var cursor = text.startIndex
        for match in all {
            let matchRange = match.range(in: text)
            if matchRange.lowerBound > cursor {
                result.append(contentsOf: text[cursor ..< matchRange.lowerBound])
            }
            result.append(transform(match))
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
    ) -> [Substring] {
        guard maxSplits >= 0 else { return [Substring(text[...])] }
        var result: [Substring] = []
        var cursor = text.startIndex
        var splitsDone = 0

        forEachMatch(in: text) { match in
            if splitsDone >= maxSplits { return false }
            let r = match.range(in: text)
            let piece = text[cursor ..< r.lowerBound]
            if !omittingEmptySubsequences || !piece.isEmpty {
                result.append(Substring(piece))
                splitsDone += 1
            }
            cursor = r.upperBound
            return splitsDone < maxSplits
        }

        let remaining = text[cursor...]
        if !omittingEmptySubsequences || !remaining.isEmpty {
            result.append(Substring(remaining))
        }
        return result
    }
}
