// @dl:accept -- the group handling of one dialect's parser: the frame types differ, so the shared part is PatternCursor
extension BTParser {
    mutating func openGroup() throws(PatternError) {
        guard frames.count <= limits.maxNestingDepth else { throw .limit(.nestingDepth) }
        let open = position
        if peek(1) == 0x3F {
            try openSpecialGroup(open: open)
        } else if peek(1) == 0x2A, !isECMAScript {
            try verb()
        } else if flags.noAutoCapture {
            push(.group(capture: nil), open: open)
            position += 1
        } else {
            try pushCapture(name: nil, open: open)
            position += 1
        }
    }

    /// `(*FAIL)` and `(*F)`; other verbs are not supported.
    private mutating func verb() throws(PatternError) {
        guard let close = scalars[position...].firstIndex(of: 0x29) else {
            throw .syntax(.unexpectedEnd, offset: offset(scalars.count))
        }
        let name = String(String.UnicodeScalarView(scalars[(position + 2) ..< close].compactMap(Unicode.Scalar.init)))
        guard name == "FAIL" || name == "F" else { throw .syntax(.unsupported, offset: offset(position)) }
        try add(.fail)
        position = close + 1
    }

    mutating func push(_ kind: BTFrame.Kind, open: Int) {
        frames.append(BTFrame(id: nextFrameId, kind: kind, openOffset: offset(open), savedFlags: flags))
        nextFrameId += 1
    }

    mutating func pushCapture(name: String?, open: Int) throws(PatternError) {
        let index = try claimCapture(named: name)
        push(.group(capture: index), open: open)
    }

    mutating func closeGroup() throws(PatternError) {
        guard frames.count > 1 else { throw .syntax(.unmatchedCloseParen, offset: offset(position)) }
        let frame = frames.removeLast()
        let node = try finishedNode(of: frame)
        if frame.resetStart != nil { captureCount = max(frame.resetHighest, captureCount) }
        flags = frame.savedFlags
        if case .look = frame.kind, top.kind == .conditional, top.condition == .lookaround, top.conditionNode == nil {
            top.conditionNode = node  // the test of a conditional is not one of its branches
        } else {
            top.items.append(node)
        }
        top.lastIsQuantified = false
        position += 1
    }

    /// The node for a group that has just closed.
    private mutating func finishedNode(of frame: BTFrame) throws(PatternError) -> Int {
        if frame.kind == .conditional { return try conditionalNode(of: frame) }
        var body = try finishBranches(of: frame)
        switch frame.kind {
            case .group(let capture?):
                return try newNode(.group(capture: capture), children: [body])
            case .look(let behind, let negative):
                return try newNode(.look(behind: behind, negative: negative), children: [body])
            case .atomic:
                return try newNode(.atomic, children: [body])
            default:
                // An assertion inside plain parentheses must stay a group, so that ECMAScript still refuses to repeat the group's body.
                if isAssertionLike(body) { body = try newNode(.concatenation, children: [body]) }
                return body
        }
    }

    /// Parses what follows `(?`.
    private mutating func openSpecialGroup(open: Int) throws(PatternError) {
        let question = offset(position + 1)
        guard let c = peek(2) else { throw .syntax(.unexpectedEnd, offset: offset(scalars.count)) }
        switch c {
            case 0x3A:
                push(.group(capture: nil), open: open)
                position += 3
            case 0x3D, 0x21:
                push(.look(behind: false, negative: c == 0x21), open: open)
                position += 3
            case 0x3E where !isECMAScript:
                push(.atomic, open: open)
                position += 3
            case 0x3C:
                if let next = peek(3), next == 0x3D || next == 0x21 {
                    push(.look(behind: true, negative: next == 0x21), open: open)
                    position += 4
                } else {
                    try openNamed(nameStart: position + 3, close: 0x3E, open: open)
                }
            case 0x50 where !isECMAScript:
                if peek(3) == 0x3D {
                    try addNamedReference(from: position + 4, close: 0x29, at: question)
                } else if peek(3) == 0x3E {
                    try addNamedCall(from: position + 4, close: 0x29, at: question)
                } else {
                    guard peek(3) == 0x3C else { throw .syntax(.unsupported, offset: question) }
                    try openNamed(nameStart: position + 4, close: 0x3E, open: open)
                }
            case 0x27 where !isECMAScript:
                try openNamed(nameStart: position + 3, close: 0x27, open: open)
            case 0x23 where !isECMAScript:
                guard let end = scalars[position...].firstIndex(of: 0x29) else {
                    throw .syntax(.unexpectedEnd, offset: offset(scalars.count))
                }
                position = end + 1
            case 0x7C where !isECMAScript:
                push(.group(capture: nil), open: open)
                top.resetStart = captureCount
                position += 3
            case 0x28 where !isECMAScript:
                try openConditional(open: open)
            case 0x52 where !isECMAScript, 0x26 where !isECMAScript, 0x30 ... 0x39 where !isECMAScript,
                0x2B where !isECMAScript:
                try parseCall(at: question)
            case 0x2D where !isECMAScript && peek(3).map({ (0x30 ... 0x39).contains($0) }) == true:
                try parseCall(at: question)
            case 0x7C, 0x28, 0x52, 0x26, 0x30 ... 0x39, 0x2B, 0x43:
                throw .syntax(.unsupported, offset: question)
            default:
                try parseFlags(open: open)
        }
    }

    private mutating func openNamed(nameStart: Int, close: UInt32, open: Int) throws(PatternError) {
        let parsed = try name(from: nameStart, until: close) { isNameScalar($0, first: $1) }
        // A branch reset may reuse a name for the same number in another branch.
        let sameNumber = names[parsed.name] == captureCount + 1
        let path = frames.flatMap { [$0.id, $0.branches.count] }
        let inOtherBranch = isECMAScript && (namePaths[parsed.name] ?? []).allSatisfy { Self.differ($0, path) }
        guard names[parsed.name] == nil || sameNumber || inOtherBranch else {
            throw .syntax(.duplicateGroupName, offset: offset(nameStart))
        }
        try pushCapture(name: parsed.name, open: open)
        namePaths[parsed.name, default: []].append(path)
        if !(groupsByName[parsed.name]?.contains(captureCount) ?? false) {
            groupsByName[parsed.name, default: []].append(captureCount)
        }
        position = parsed.end + 1
    }

    /// Whether two groups' paths hold them in different branches of some shared group, so they can never both take part in a match.
    private static func differ(_ a: [Int], _ b: [Int]) -> Bool {
        var index = 0
        while index + 1 < a.count, index + 1 < b.count {
            if a[index] != b[index] { return false }
            if a[index + 1] != b[index + 1] { return true }
            index += 2
        }
        return false
    }

    func isNameScalar(_ c: UInt32, first: Bool) -> Bool {
        if !isECMAScript, c < 0x80 {
            switch c {
                case 0x41 ... 0x5A, 0x61 ... 0x7A, 0x5F: return true
                case 0x30 ... 0x39: return !first
                default: return false
            }
        }
        if c == 0x24 || c == 0x5F { return true }
        guard let scalar = Unicode.Scalar(c) else { return false }
        if first { return scalar.properties.isIDStart }
        return scalar.properties.isIDContinue || c == 0x200C || c == 0x200D
    }

    /// `(?flags)` changes the flags until the enclosing group ends; `(?flags:…)` opens a group that has them.
    private mutating func parseFlags(open: Int) throws(PatternError) {
        var updated = flags
        let scan = try scanFlags(
            from: position + 2, closers: isECMAScript ? [0x3A] : [0x29, 0x3A], allowEmptyNegation: !isECMAScript
        ) { letter, on in
            switch letter {
                case 0x69: updated.ignoreCase = !on
                case 0x6D: updated.multiLine = !on
                case 0x73: updated.dotAll = !on
                case 0x78 where !isECMAScript: updated.extended = !on
                case 0x6E where !isECMAScript: updated.noAutoCapture = !on
                default: return false
            }
            return true
        }
        if isECMAScript, !scan.sawFlag, scan.end == position + 2 {
            throw .syntax(.invalidFlag, offset: offset(scan.end))
        }
        if scan.closer == 0x3A { push(.group(capture: nil), open: open) }
        flags = updated
        position = scan.end + 1
    }

    /// How many capture groups the whole pattern has, counted without parsing it: PCRE2 reads `\10` as a back reference only if the
    /// pattern has that many groups, wherever they are.
    func countGroups() -> Int {
        var count = 0
        var index = 0
        var inClass = false
        while index < scalars.count {
            let c = scalars[index]
            if c == 0x5C {
                index += 2
                continue
            }
            if inClass {
                if c == 0x5D { inClass = false }
            } else if c == 0x5B {
                inClass = true
                if index + 1 < scalars.count, scalars[index + 1] == 0x5E { index += 1 }
                if index + 1 < scalars.count, scalars[index + 1] == 0x5D, !isECMAScript { index += 1 }
            } else if c == 0x28 {
                let next = index + 1 < scalars.count ? scalars[index + 1] : 0
                let after = index + 2 < scalars.count ? scalars[index + 2] : 0
                if next != 0x3F, next != 0x2A {
                    count += 1
                } else if next == 0x3F {
                    let third = index + 3 < scalars.count ? scalars[index + 3] : 0
                    if after == 0x27 || (after == 0x3C && third != 0x3D && third != 0x21)
                        || (after == 0x50 && third == 0x3C)
                    {
                        count += 1
                    }
                }
            }
            index += 1
        }
        return count
    }
}
