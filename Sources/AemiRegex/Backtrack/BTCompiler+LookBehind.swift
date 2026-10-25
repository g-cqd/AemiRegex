extension BTCompiler {
    /// The body of a PCRE2 look-behind: for each branch, every start from the farthest back to the nearest, each reading the branch forward
    /// and requiring it to end where the look-behind began.
    ///
    /// - Throws: ``PatternError/Reason/unboundedLookbehind`` when a branch can be longer than 255 scalars, as in PCRE2.
    func pcreLookbehindBody(_ branches: [BTFragment]) throws(PatternError) -> BTFragment {
        var coded: [BTFragment] = []
        for branch in branches {
            guard let longest = branch.maxLength, longest <= 255 else { throw .syntax(.unboundedLookbehind, offset: 0) }
            var tail: [BTInstruction] = []
            for length in branch.minLength ... longest {
                var attempt = length == 0 ? [] : [BTInstruction(.stepBack, length)]
                attempt += branch.code
                if longest != branch.minLength { attempt.append(BTInstruction(.endAt)) }
                tail =
                    tail.isEmpty
                    ? attempt
                    : [BTInstruction(.split, 1, attempt.count + 2)] + attempt + [BTInstruction(.jump, tail.count + 1)]
                        + tail
            }
            var copy = branch
            copy.code = tail
            coded.append(copy)
        }
        return alternation(coded)
    }
}
