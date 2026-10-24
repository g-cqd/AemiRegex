extension Parser {
    /// Parses what follows `(?`: a non-capturing group, a named group, or flags.
    mutating func openSpecialGroup(open: Int) throws(PatternError) {
        let question = position + 1
        guard let c = peek(2) else { throw .syntax(.unexpectedEnd, offset: offset(scalars.count)) }
        switch c {
            case 0x3A:
                frames.append(Frame(kind: .group(capture: nil), openOffset: offset(open), savedFlags: flags))
                position += 3
            case 0x50:
                guard peek(3) == 0x3C else { throw .syntax(.invalidGroupSyntax, offset: offset(question)) }
                try openNamed(nameStart: position + 4, open: open)
            case 0x3C:
                if let next = peek(3), next == 0x3D || next == 0x21 {
                    throw .syntax(.unsupported, offset: offset(question))
                }
                try openNamed(nameStart: position + 3, open: open)
            case 0x3D, 0x21, 0x3E:
                throw .syntax(.unsupported, offset: offset(question))
            case 0x23, 0x7C:
                throw .syntax(.invalidGroupSyntax, offset: offset(question))
            default:
                try parseFlags(open: open)
        }
    }

    private mutating func openNamed(nameStart: Int, open: Int) throws(PatternError) {
        var end = nameStart
        while end < scalars.count, scalars[end] != 0x3E {
            guard Self.isNameScalar(scalars[end], first: end == nameStart) else {
                throw .syntax(.invalidGroupName, offset: offset(end))
            }
            end += 1
        }
        guard end < scalars.count, end > nameStart else { throw .syntax(.invalidGroupName, offset: offset(nameStart)) }
        var text = ""
        for scalar in scalars[nameStart ..< end] { text.unicodeScalars.append(Unicode.Scalar(scalar) ?? "_") }
        guard names[text] == nil else { throw .syntax(.duplicateGroupName, offset: offset(nameStart)) }
        try pushCapture(name: text, open: open)
        position = end + 1
    }

    private static func isNameScalar(_ c: UInt32, first: Bool) -> Bool {
        switch c {
            case 0x41 ... 0x5A, 0x61 ... 0x7A, 0x5F: true
            case 0x30 ... 0x39: !first
            default: false
        }
    }

    /// `(?flags)` changes the flags until the enclosing group ends; `(?flags:…)` opens a group that has them.
    private mutating func parseFlags(open: Int) throws(PatternError) {
        var updated = flags
        var negating = false
        var sawFlag = false
        var index = position + 2
        while true {
            guard index < scalars.count else { throw .syntax(.unexpectedEnd, offset: offset(scalars.count)) }
            let c = scalars[index]
            switch c {
                case 0x69, 0x6D, 0x73, 0x55:
                    switch c {
                        case 0x69: updated.ignoreCase = !negating
                        case 0x6D: updated.multiLine = !negating
                        case 0x73: updated.dotAll = !negating
                        default: updated.swapGreed = !negating
                    }
                    sawFlag = true
                case 0x2D:
                    guard !negating else { throw .syntax(.invalidFlag, offset: offset(index)) }
                    negating = true
                    sawFlag = false
                case 0x29, 0x3A:
                    if negating, !sawFlag { throw .syntax(.invalidFlag, offset: offset(index)) }
                    if c == 0x3A {
                        frames.append(Frame(kind: .group(capture: nil), openOffset: offset(open), savedFlags: flags))
                    } else {
                        top.last = nil
                        top.lastWasRepetition = false
                    }
                    flags = updated
                    position = index + 1
                    return
                default:
                    throw .syntax(.invalidFlag, offset: offset(index))
            }
            index += 1
        }
    }
}
