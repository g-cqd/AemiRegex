/// Parses a pattern and compiles it in one pass, without a syntax tree and without recursion: groups live on an explicit stack.
struct Parser: PatternCursor {
    let scalars: [UInt32]
    /// `offsets[i]` is the UTF-8 offset of `scalars[i]`; the last entry is the pattern's length in bytes.
    let offsets: [Int]
    let limits: Pattern.Limits
    /// Builds the program for the reversed pattern (atoms in reverse order, UTF-8 sequences reversed), used to find match starts.
    let reverse: Bool
    /// The whole program must match the entire text: anchors are added around the finished alternation, not written into the text.
    let wholeString: Bool
    var position = 0
    var flags = Flags()
    var frames: [Frame]
    var captureCount = 0
    var names: [String: Int] = [:]
    var classes = ClassCompiler()
    /// Instructions emitted so far, counted conservatively, to enforce ``Pattern/Limits/maxProgramSize``.
    var emitted = 0

    private init(_ pattern: String, limits: Pattern.Limits, reverse: Bool, wholeString: Bool) {
        let text = PatternText(pattern)
        scalars = text.scalars
        offsets = text.offsets
        self.limits = limits
        self.reverse = reverse
        self.wholeString = wholeString
        frames = [Frame(kind: .root, openOffset: 0, savedFlags: Flags())]
    }

    static func compile(
        _ pattern: String, limits: Pattern.Limits, reverse: Bool = false, wholeString: Bool = false
    ) throws(PatternError) -> Program {
        guard pattern.utf8.count <= limits.maxPatternBytes else { throw .limit(.patternLength) }
        var parser = Parser(pattern, limits: limits, reverse: reverse, wholeString: wholeString)
        return try parser.parse()
    }

    var top: Frame {
        get { frames[frames.count - 1] }
        _modify { yield &frames[frames.count - 1] }
    }

    mutating func parse() throws(PatternError) -> Program {
        while position < scalars.count { try step() }
        guard frames.count == 1 else { throw .syntax(.unmatchedOpenParen, offset: top.openOffset) }
        emitted += 2 * top.branches.count
        try checkSize()
        var code = top.finished(reversed: reverse).code
        if wholeString {
            // The same text order in both directions: the first instruction is the edge where the scan starts, the last the edge where it ends.
            code = [.assertion(.beginText)] + code + [.assertion(.endText)]
            emitted += 2
            try checkSize()
        }
        var instructions = ContiguousArray(code)
        instructions.append(.match)
        guard instructions.count * 2 * (captureCount + 1) <= limits.maxThreadTableEntries else {
            throw .limit(.programSize)
        }
        return Program(instructions: instructions, sets: classes.sets, captureCount: captureCount, names: names)
    }

    private mutating func step() throws(PatternError) {
        let c = scalars[position]
        switch c {
            case 0x28: try openGroup()
            case 0x29: try closeGroup()
            case 0x7C:
                emitted += 2
                top.startNextBranch()
                position += 1
            case 0x2A: try repeatOperator(min: 0, max: nil, length: 1)
            case 0x2B: try repeatOperator(min: 1, max: nil, length: 1)
            case 0x3F: try repeatOperator(min: 0, max: 1, length: 1)
            case 0x7B:
                if let braces = try parseBraces() {
                    try repeatOperator(min: braces.min, max: braces.max, length: braces.length)
                } else {
                    try emitLiteral(c)
                    position += 1
                }
            case 0x5B: try parseClass()
            case 0x2E:
                try emitSet(
                    flags.dotAll ? ScalarSet(normalizing: [0 ... ScalarSet.maxScalar]) : ScalarSet.newline.negated())
                position += 1
            case 0x5E:
                try emit([.assertion(oriented(flags.multiLine ? .beginLine : .beginText))], nullable: true)
                position += 1
            case 0x24:
                try emit([.assertion(oriented(flags.multiLine ? .endLine : .endText))], nullable: true)
                position += 1
            case 0x5C: try parseEscapeAtom()
            default:
                try emitLiteral(c)
                position += 1
        }
    }

    // MARK: Emitting

    /// An assertion as the program being built reads the text: mirrored in the reverse program.
    func oriented(_ assertion: Assertion) -> Assertion { reverse ? assertion.mirrored : assertion }

    mutating func checkSize() throws(PatternError) {
        if emitted > limits.maxProgramSize { throw .limit(.programSize) }
    }

    mutating func emit(_ code: [Instruction], nullable: Bool) throws(PatternError) {
        emitted += code.count
        try checkSize()
        top.push(code, nullable: nullable)
    }

    mutating func emitSet(_ set: ScalarSet) throws(PatternError) {
        try emit(classes.compile(set, reversed: reverse), nullable: false)
    }

    mutating func emitLiteral(_ scalar: UInt32) throws(PatternError) {
        let set = ScalarSet(scalar)
        try emitSet(flags.ignoreCase ? set.folded() : set)
    }

    // MARK: Groups

    private mutating func openGroup() throws(PatternError) {
        guard frames.count <= limits.maxNestingDepth else { throw .limit(.nestingDepth) }
        let open = position
        if peek(1) == 0x3F {
            try openSpecialGroup(open: open)
        } else {
            try pushCapture(name: nil, open: open)
            position += 1
        }
    }

    mutating func pushCapture(name: String?, open: Int) throws(PatternError) {
        let index = try claimCapture(named: name)
        frames.append(Frame(kind: .group(capture: index), openOffset: offset(open), savedFlags: flags))
    }

    private mutating func closeGroup() throws(PatternError) {
        guard frames.count > 1 else { throw .syntax(.unmatchedCloseParen, offset: offset(position)) }
        let frame = frames.removeLast()
        emitted += 2 * frame.branches.count
        let (body, nullable) = frame.finished(reversed: reverse)
        var code = body
        if !reverse, case .group(let capture?) = frame.kind {
            code = [.save(2 * capture)] + body + [.save(2 * capture + 1)]
            emitted += 2
        }
        try checkSize()
        flags = frame.savedFlags
        top.push(code, nullable: nullable)
        position += 1
    }
}
