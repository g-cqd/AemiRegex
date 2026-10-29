internal import AemiUnicode

/// Parses ECMAScript and PCRE2 syntax into a ``BTSyntaxTree``. Groups live on an explicit stack, so no pattern can overflow the call stack.
struct BTParser: PatternCursor {
    let scalars: [UInt32]
    /// `offsets[i]` is the UTF-8 offset of `scalars[i]`; the last entry is the pattern's length.
    let offsets: [Int]
    let dialect: BacktrackingPattern.Dialect
    let limits: Pattern.Limits
    var position = 0
    var flags = BTFlags()
    var nodes: [BTNode] = []
    var sets: [CharSet] = []
    var frames: [BTFrame] = [BTFrame(id: 0, kind: .root, openOffset: 0, savedFlags: BTFlags())]
    var captureCount = 0
    var names: [String: Int] = [:]
    /// Where each group with a name sits: per group, the (frame, branch) pairs from the root. ECMAScript allows a name twice only when
    /// some frame holds the two groups in different branches.
    var namePaths: [String: [[Int]]] = [:]
    var groupsByName: [String: [Int]] = [:]
    var nextFrameId = 1
    /// Back references to check once the group count is known.
    var pendingGroups: [(group: Int, offset: Int)] = []
    var pendingNames: [(name: String, offset: Int)] = []
    /// The number of capture groups in the whole pattern, which PCRE2 needs to read `\10` before the groups are seen.
    var totalGroups = 0

    var isECMAScript: Bool { dialect == .ecmaScript }

    private init(
        _ pattern: String, dialect: BacktrackingPattern.Dialect, options: BacktrackingPattern.Options,
        limits: Pattern.Limits
    ) {
        let text = PatternText(pattern)
        scalars = text.scalars
        offsets = text.offsets
        self.dialect = dialect
        self.limits = limits
        flags = BTFlags(
            ignoreCase: options.contains(.ignoreCase), multiLine: options.contains(.multiLine),
            dotAll: options.contains(.dotAll), extended: options.contains(.extended),
            unicodeSets: options.contains(.unicodeSets))
    }

    static func parse(
        _ pattern: String, dialect: BacktrackingPattern.Dialect, options: BacktrackingPattern.Options = [],
        limits: Pattern.Limits
    ) throws(PatternError) -> BTSyntaxTree {
        guard pattern.utf8.count <= limits.maxPatternBytes else { throw .limit(.patternLength) }
        guard dialect == .pcre2 || !options.contains(.extended) else { throw .syntax(.invalidFlag, offset: 0) }
        // @dl:accept -- the entry point of one dialect's parser; the shared decoding is PatternCursor
        guard dialect == .ecmaScript || !options.contains(.unicodeSets) else { throw .syntax(.invalidFlag, offset: 0) }
        var parser = BTParser(pattern, dialect: dialect, options: options, limits: limits)
        return try parser.run()
    }

    var top: BTFrame {
        get { frames[frames.count - 1] }
        _modify { yield &frames[frames.count - 1] }
    }

    private mutating func run() throws(PatternError) -> BTSyntaxTree {
        totalGroups = countGroups()
        while position < scalars.count { try step() }
        guard frames.count == 1 else { throw .syntax(.unmatchedOpenParen, offset: top.openOffset) }
        let root = try finishBranches(of: frames[0])
        for reference in pendingGroups where reference.group > captureCount {
            throw .syntax(.invalidEscape, offset: reference.offset)
        }
        for reference in pendingNames where groupsByName[reference.name] == nil {
            throw .syntax(.invalidGroupName, offset: reference.offset)
        }
        return BTSyntaxTree(nodes: nodes, root: root, sets: sets, captureCount: captureCount, names: groupsByName)
    }

    private mutating func step() throws(PatternError) {
        let c = scalars[position]
        if flags.extended, skipExtendedText(c) { return }
        switch c {
            case 0x28: try openGroup()
            case 0x29: try closeGroup()
            case 0x7C:
                if let start = top.resetStart {
                    top.resetHighest = max(top.resetHighest, captureCount)
                    captureCount = start
                }
                let branch = try concatenation(of: top.items)
                top.branches.append(branch)
                top.items = []
                top.lastIsQuantified = false
                // @dl:accept -- the dispatch of one dialect's parser: its shape follows the syntax, its handlers are its own
                position += 1
            case 0x2A: try quantify(min: 0, max: nil, length: 1)
            case 0x2B: try quantify(min: 1, max: nil, length: 1)
            case 0x3F: try quantify(min: 0, max: 1, length: 1)
            case 0x7B:
                if let braces = try parseBraces() {
                    try quantify(min: braces.min, max: braces.max, length: braces.length)
                } else if isECMAScript {
                    throw .syntax(.invalidRepetition, offset: offset(position))
                } else {
                    try addLiteral(c)
                    position += 1
                }
            case 0x7D, 0x5D:
                if isECMAScript { throw .syntax(.invalidCharacter, offset: offset(position)) }
                try addLiteral(c)
                position += 1
            case 0x5B: try (flags.unicodeSets ? parseSetClass() : parseClass())
            case 0x2E:
                let lines = BTSets.lineTerminators(dialect)
                try addSet(
                    flags.dotAll ? UnicodeScalarSet(normalizing: [0 ... UnicodeScalarSet.maxScalar]) : lines.negated())
                position += 1
            case 0x5E:
                try add(.assertion(flags.multiLine ? .beginLine : .beginText))
                position += 1
            case 0x24:
                let plain: BTAssertion = isECMAScript ? .endText : .endTextBeforeFinalNewline
                try add(.assertion(flags.multiLine ? .endLine : plain))
                position += 1
            case 0x5C: try parseAtomEscape()
            default:
                try addLiteral(c)
                position += 1
        }
    }

    /// PCRE2's `x`: white space is ignored and `#` starts a comment that runs to the end of the line. Returns whether `c` was skipped.
    private mutating func skipExtendedText(_ c: UInt32) -> Bool {
        if c == 0x20 || (0x09 ... 0x0D).contains(c) {
            position += 1
            return true
        }
        guard c == 0x23 else { return false }
        while position < scalars.count, scalars[position] != 0x0A { position += 1 }
        return true
    }

    // MARK: Nodes

    /// Adds a node to the arena and to the current branch.
    mutating func add(_ kind: BTNode.Kind, children: [Int] = []) throws(PatternError) {
        let index = try newNode(kind, children: children)
        top.items.append(index)
        top.lastIsQuantified = false
    }

    mutating func newNode(_ kind: BTNode.Kind, children: [Int] = []) throws(PatternError) -> Int {
        guard nodes.count < limits.maxProgramSize else { throw .limit(.programSize) }
        nodes.append(BTNode(kind: kind, children: children))
        return nodes.count - 1
    }

    mutating func addSet(_ set: UnicodeScalarSet) throws(PatternError) {
        sets.append(CharSet(set))
        try add(.set(sets.count - 1))
    }

    /// A literal scalar, folded when `i` is on.
    mutating func addLiteral(_ scalar: UInt32) throws(PatternError) {
        let set = UnicodeScalarSet(scalar)
        try addSet(flags.ignoreCase ? set.simpleCaseClosure() : set)
    }

    /// The node for items matched one after another.
    mutating func concatenation(of items: [Int]) throws(PatternError) -> Int {
        switch items.count {
            case 0: try newNode(.empty)
            case 1: items[0]
            default: try newNode(.concatenation, children: items)
        }
    }

    /// The node for all branches of a frame, the last branch being its current items.
    mutating func finishBranches(of frame: BTFrame) throws(PatternError) -> Int {
        let last = try concatenation(of: frame.items)
        guard !frame.branches.isEmpty else { return last }
        return try newNode(.alternation, children: frame.branches + [last])
    }
}
