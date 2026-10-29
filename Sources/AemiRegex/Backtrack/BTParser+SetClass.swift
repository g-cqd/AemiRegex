internal import AemiUnicode

extension BTParser {
    /// Reads a class in `v` mode: operands (characters, ranges, escapes, `\q{…}` strings, nested classes) joined by union, `--` or `&&`.
    /// Classes nest on an explicit stack. A class that holds strings becomes an alternation, longest string first.
    mutating func parseSetClass() throws(PatternError) {
        var stack = [try openSetFrame()]
        while true {
            guard let c = peek() else { throw .syntax(.unterminatedClass, offset: stack[0].openOffset) }
            let last = stack.count - 1
            if c == 0x5D {
                position += 1
                let finished = try finish(stack[last])
                stack.removeLast()
                guard !stack.isEmpty else { return try addStringSet(finished) }
                guard stack[stack.count - 1].feed(finished) else {
                    throw .syntax(.invalidClassRange, offset: offset(position))
                }
                stack[stack.count - 1].lastWasRange = false
            } else if c == 0x5B {
                guard stack.count <= limits.maxNestingDepth else { throw .limit(.nestingDepth) }
                stack.append(try openSetFrame())
            } else if c == 0x2D || c == 0x26, peek(1) == c {
                try setOperator(c, in: &stack[last])
            } else {
                let (operand, isRange) = try setOperand()
                // A range joins a union only: `--` and `&&` take single characters, classes and strings.
                let combines = stack[last].pendingOperator || stack[last].combination.isOperator
                guard !(isRange && combines), stack[last].feed(operand) else {
                    throw .syntax(.invalidClassRange, offset: offset(position))
                }
                stack[last].lastWasRange = isRange
            }
        }
    }

    private mutating func openSetFrame() throws(PatternError) -> BTSetFrame {
        let open = offset(position)
        position += 1
        let negated = peek() == 0x5E
        if negated { position += 1 }
        return BTSetFrame(negated: negated, openOffset: open)
    }

    /// `--` or `&&` after the first operand (or a chain of the same one): the next operand is combined that way.
    private mutating func setOperator(_ c: UInt32, in frame: inout BTSetFrame) throws(PatternError) {
        let wanted: BTSetFrame.Combination = c == 0x2D ? .subtraction : .intersection
        let first = frame.operandCount == 1 && frame.combination == .none
        guard !frame.pendingOperator, !frame.lastWasRange, first || frame.combination == wanted else {
            throw .syntax(.invalidClassRange, offset: offset(position))
        }
        if c == 0x26, peek(2) == 0x26 { throw .syntax(.invalidClassRange, offset: offset(position)) }
        frame.combination = wanted
        frame.pendingOperator = true
        position += 2
    }

    private func finish(_ frame: BTSetFrame) throws(PatternError) -> BTStringSet {
        guard !frame.pendingOperator else { throw .syntax(.invalidClassRange, offset: frame.openOffset) }
        var value = frame.value ?? BTStringSet()
        if frame.negated {
            // A class that can match a string cannot be complemented.
            guard value.strings.isEmpty else { throw .syntax(.invalidClassRange, offset: frame.openOffset) }
            value = BTStringSet(scalars: value.scalars.negated())
        }
        return value
    }

    /// A character or range, a class escape, or `\q{…}`.
    /// - Returns: The operand, and whether it was a range.
    private mutating func setOperand() throws(PatternError) -> (BTStringSet, isRange: Bool) {
        let ignoreCase = flags.ignoreCase
        func fold(_ set: UnicodeScalarSet) -> UnicodeScalarSet { ignoreCase ? set.simpleCaseClosure() : set }
        if peek() == 0x5C, peek(1) == 0x71 { return (try quotedStrings(), false) }
        if peek() == 0x5C, let next = peek(1), "dDwWsSpP".unicodeScalars.contains(where: { $0.value == next }) {
            switch try parseCharacterEscape(inClass: true) {
                case .set(let set), .fixedSet(let set): return (BTStringSet(scalars: fold(set)), false)
                case .scalar(let scalar): return (BTStringSet(scalars: fold(UnicodeScalarSet(scalar))), false)
            }
        }
        let low = try setCharacter()
        guard peek() == 0x2D, peek(1) != 0x2D else { return (BTStringSet(scalars: fold(UnicodeScalarSet(low))), false) }
        position += 1
        let high = try setCharacter()
        guard low <= high else { throw .syntax(.invalidClassRange, offset: offset(position)) }
        return (BTStringSet(scalars: fold(UnicodeScalarSet(normalizing: [low ... high]))), true)
    }

    /// `\q{abc|d|}`: strings that the class matches, longest first.
    private mutating func quotedStrings() throws(PatternError) -> BTStringSet {
        let at = offset(position)
        position += 2
        guard peek() == 0x7B else { throw .syntax(.invalidEscape, offset: at) }
        position += 1
        var result = BTStringSet()
        var current: [UInt32] = []
        while true {
            guard let c = peek() else { throw .syntax(.unexpectedEnd, offset: offset(scalars.count)) }
            if c == 0x7D || c == 0x7C {
                position += 1
                result.insert(current)
                current = []
                if c == 0x7D { break }
            } else {
                current.append(try setCharacter())
            }
        }
        return result.mappingScalars { flags.ignoreCase ? $0.simpleCaseClosure() : $0 }
    }

    /// One scalar of a class in `v` mode. Syntax characters must be escaped, and so must the second of a doubled punctuator.
    private mutating func setCharacter() throws(PatternError) -> UInt32 {
        let at = offset(position)
        guard let c = peek() else { throw .syntax(.unterminatedClass, offset: at) }
        if c == 0x5C {
            guard let next = peek(1) else { throw .syntax(.unexpectedEnd, offset: at) }
            if Self.isSetEscapable(next) {
                position += 2
                return next
            }
            switch try parseCharacterEscape(inClass: true) {
                case .scalar(let scalar): return scalar
                case .set, .fixedSet: throw .syntax(.invalidClassRange, offset: at)
            }
        }
        guard !Self.isSetSyntax(c), !(Self.isDoubledPunctuator(c) && peek(1) == c) else {
            throw .syntax(.invalidCharacter, offset: at)
        }
        position += 1
        return c
    }

    /// `( ) [ ] { } / - \ |`: written only with a backslash in a class in `v` mode.
    private static func isSetSyntax(_ c: UInt32) -> Bool { "()[]{}/-\\|".unicodeScalars.contains { $0.value == c } }

    /// The punctuators a class may escape: the syntax characters and `& ! # % , : ; < = > @ \` ~`.
    private static func isSetEscapable(_ c: UInt32) -> Bool {
        isSetSyntax(c) || "&!#%,:;<=>@`~".unicodeScalars.contains { $0.value == c }
    }

    /// `& ! # $ % * + , . : ; < = > ? @ ^ \` ~`: two in a row are reserved.
    private static func isDoubledPunctuator(_ c: UInt32) -> Bool {
        "&!#$%*+,.:;<=>?@^`~".unicodeScalars.contains { $0.value == c }
    }

    /// Adds what a finished class denotes: a set, or an alternation of its strings (longest first), its scalars, and the empty string.
    private mutating func addStringSet(_ value: BTStringSet) throws(PatternError) {
        guard !value.strings.isEmpty else { return try addSet(value.scalars) }
        var branches: [Int] = []
        let strings = value.strings.filter { !$0.isEmpty }
            .sorted {
                $0.count != $1.count ? $0.count > $1.count : $0.lexicographicallyPrecedes($1)
            }
        for string in strings {
            var items: [Int] = []
            for scalar in string {
                sets.append(
                    CharSet(flags.ignoreCase ? UnicodeScalarSet(scalar).simpleCaseClosure() : UnicodeScalarSet(scalar)))
                items.append(try newNode(.set(sets.count - 1)))
            }
            branches.append(try newNode(.concatenation, children: items))
        }
        if !value.scalars.isEmpty {
            sets.append(CharSet(value.scalars))
            branches.append(try newNode(.set(sets.count - 1)))
        }
        if value.strings.contains([]) { branches.append(try newNode(.empty)) }
        let alternation = try newNode(.alternation, children: branches)
        top.items.append(try newNode(.concatenation, children: [alternation]))
        top.lastIsQuantified = false
    }
}
