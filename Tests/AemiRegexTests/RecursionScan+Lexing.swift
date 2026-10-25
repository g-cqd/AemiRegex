import Foundation

extension RecursionScan {
    // MARK: Lexing

    /// The text with comments and string literals replaced by spaces, newlines kept, so braces and parentheses inside them cannot confuse
    /// the scan.
    static func blank(_ text: String, language: Language) -> String {
        let scalars = Array(text.unicodeScalars)
        var out = String.UnicodeScalarView()
        var index = 0
        func blankRun(_ end: Int) {
            while index < end {
                out.append(scalars[index] == "\n" ? "\n" : " ")
                index += 1
            }
        }
        while index < scalars.count {
            let c = scalars[index]
            let next = index + 1 < scalars.count ? scalars[index + 1] : " "
            if c == "/", next == "/" {
                var end = index
                while end < scalars.count, scalars[end] != "\n" { end += 1 }
                blankRun(end)
            } else if c == "/", next == "*" {
                var end = index + 2
                while end + 1 < scalars.count, !(scalars[end] == "*" && scalars[end + 1] == "/") { end += 1 }
                blankRun(min(end + 2, scalars.count))
            } else if language == .swift, c == "\"", index + 2 < scalars.count, scalars[index + 1] == "\"",
                scalars[index + 2] == "\""
            {
                var end = index + 3
                while end + 2 < scalars.count,
                    !(scalars[end] == "\"" && scalars[end + 1] == "\"" && scalars[end + 2] == "\"")
                { end += 1 }
                blankRun(min(end + 3, scalars.count))
            } else if c == "\"" || (language == .go && (c == "`" || c == "'")) {
                var end = index + 1
                while end < scalars.count, scalars[end] != c {
                    if scalars[end] == "\\", c != "`" { end += 1 }
                    if scalars[end] == "\n", c != "`" { break }
                    end += 1
                }
                blankRun(min(end + 1, scalars.count))
            } else {
                out.append(c)
                index += 1
            }
        }
        return String(out)
    }

    static func isIdentifier(_ c: Unicode.Scalar) -> Bool {
        c == "_" || (c.value >= 0x30 && c.value <= 0x39) || (c.value >= 0x41 && c.value <= 0x5A)
            || (c.value >= 0x61 && c.value <= 0x7A)
    }

    static func isBoundary(before index: Int, in source: [Unicode.Scalar]) -> Bool {
        index == 0 || !isIdentifier(source[index - 1])
    }

    static func matches(_ word: String, at index: Int, in source: [Unicode.Scalar]) -> Bool {
        let scalars = Array(word.unicodeScalars)
        guard index + scalars.count < source.count else { return false }
        return Array(source[index ..< index + scalars.count]) == scalars && !isIdentifier(source[index + scalars.count])
    }

    static func skipSpace(_ index: Int, _ source: [Unicode.Scalar]) -> Int {
        var cursor = index
        while cursor < source.count, source[cursor] == " " || source[cursor] == "\n" || source[cursor] == "\t" {
            cursor += 1
        }
        return min(cursor, max(source.count - 1, 0))
    }

    /// The index of the bracket that closes the one at `open`, or the last index when unbalanced.
    static func closing(of open: Int, in source: [Unicode.Scalar]) -> Int {
        let pairs: [Unicode.Scalar: Unicode.Scalar] = ["(": ")", "{": "}", "[": "]", "<": ">"]
        guard open < source.count, let closer = pairs[source[open]] else { return min(open, source.count - 1) }
        var depth = 0
        var index = open
        while index < source.count {
            if source[index] == source[open] { depth += 1 }
            if source[index] == closer, !(closer == ">" && index > 0 && source[index - 1] == "-") {
                depth -= 1
                if depth == 0 { return index }
            }
            index += 1
        }
        return source.count - 1
    }

    /// The `{` that opens the body of a function whose parameter list ends at `end`, or `nil` for a declaration without one.
    static func bodyStart(after end: Int, in source: [Unicode.Scalar]) -> Int? {
        var index = end + 1
        var depth = 0
        while index < source.count {
            let c = source[index]
            if c == "(" || c == "[" { depth += 1 }
            if c == ")" || c == "]" { depth -= 1 }
            if depth == 0, c == "{" { return index }
            if depth == 0, c == "}" || (c == "\n" && lineStartsDeclaration(after: index, in: source)) { return nil }
            index += 1
        }
        return nil
    }

    static func lineStartsDeclaration(after newline: Int, in source: [Unicode.Scalar]) -> Bool {
        let start = skipSpace(newline + 1, source)
        return [
            "func", "var", "let", "case", "init", "static", "private", "public", "internal", "enum", "struct",
            "protocol", "extension"
        ]
        .contains { matches($0, at: start, in: source) }
    }
}
