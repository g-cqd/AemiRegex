import Foundation

/// A heuristic scan for functions that reach themselves, directly or through others: ADR-0003 says nothing may.
///
/// It reads source, not types, so it is a guard and not a proof. A function is identified by its name and argument labels, so overloads
/// that differ in labels are distinct. A call counts when it is unqualified or goes through `self` or `Self`; a call through another
/// receiver (`array.append(x)`) does not, which keeps `Array.append` from looking like our own `append`, and means recursion through
/// another receiver of the same type is not seen. Trailing-closure calls, computed properties and initialisers are not scanned.
enum RecursionScan {
    /// What is wrong in these sources, one sentence per cycle; empty when no function reaches itself.
    static func findings(swift: [(name: String, text: String)], go: [(name: String, text: String)]) -> [String] {
        var problems: [String] = []
        problems += cycles(in: swift.flatMap { definitions(in: $0.text, name: $0.name, language: .swift) })
        problems += cycles(in: go.flatMap { definitions(in: $0.text, name: $0.name, language: .go) })
        return problems
    }

    enum Language { case swift, go }

    struct Definition {
        let key: String
        let file: String
        let calls: Set<String>
    }

    // MARK: Cycles (explicit stack: the scanner follows its own rule)

    private static func cycles(in definitions: [Definition]) -> [String] {
        var edges: [String: Set<String>] = [:]
        var files: [String: String] = [:]
        for definition in definitions {
            edges[definition.key, default: []].formUnion(definition.calls)
            files[definition.key] = definition.file
        }
        let known = Set(edges.keys)
        var reported: Set<String> = []
        var problems: [String] = []
        var finished: Set<String> = []
        for start in edges.keys.sorted() where !finished.contains(start) {
            // Each stack entry is a node and the callees not yet explored from it; `onPath` is the current path.
            var stack: [(node: String, pending: [String])] = [
                (start, (edges[start] ?? []).intersection(known).sorted())
            ]
            var path = [start]
            var onPath: Set<String> = [start]
            while var top = stack.popLast() {
                guard let next = top.pending.popLast() else {
                    finished.insert(top.node)
                    onPath.remove(top.node)
                    path.removeLast()
                    continue
                }
                stack.append(top)
                if onPath.contains(next) {
                    let cycle = Array(path[(path.firstIndex(of: next) ?? 0)...]) + [next]
                    let label = cycle.joined(separator: " -> ")
                    if reported.insert(Set(cycle).sorted().joined()).inserted {
                        problems.append("\(files[next] ?? "?"): \(label)")
                    }
                } else if !finished.contains(next) {
                    stack.append((next, (edges[next] ?? []).intersection(known).sorted()))
                    path.append(next)
                    onPath.insert(next)
                }
            }
        }
        return problems
    }

    // MARK: Reading definitions

    static func definitions(in text: String, name: String, language: Language) -> [Definition] {
        let source = Array(blank(text, language: language).unicodeScalars)
        var result: [Definition] = []
        var index = 0
        while index < source.count {
            guard matches("func", at: index, in: source), isBoundary(before: index, in: source),
                index + 4 < source.count
            else {
                index += 1
                continue
            }
            var cursor = index + 4
            if language == .go, source[skipSpace(cursor, source)] == "(" {  // a Go method receiver
                cursor = closing(of: skipSpace(cursor, source), in: source) + 1
            }
            cursor = skipSpace(cursor, source)
            let nameStart = cursor
            while cursor < source.count, isIdentifier(source[cursor]) { cursor += 1 }
            guard cursor > nameStart else {
                index += 4
                continue
            }
            let functionName = String(String.UnicodeScalarView(source[nameStart ..< cursor]))
            cursor = skipSpace(cursor, source)
            if cursor < source.count, source[cursor] == "<" { cursor = closing(of: cursor, in: source) + 1 }
            cursor = skipSpace(cursor, source)
            guard cursor < source.count, source[cursor] == "(" else {
                index = cursor
                continue
            }
            let parametersEnd = closing(of: cursor, in: source)
            let labels = language == .swift ? parameterLabels(Array(source[(cursor + 1) ..< parametersEnd])) : []
            guard let open = bodyStart(after: parametersEnd, in: source) else {
                index = parametersEnd
                continue
            }
            let close = closing(of: open, in: source)
            let body = Array(source[(open + 1) ..< close])
            let key = language == .swift ? "\(functionName)(\(labels.map { $0 + ":" }.joined()))" : functionName
            result.append(Definition(key: key, file: name, calls: calls(in: body, language: language)))
            index = close
        }
        return result
    }

    private static func calls(in body: [Unicode.Scalar], language: Language) -> Set<String> {
        var found: Set<String> = []
        var index = 0
        let keywords: Set<String> = [
            "if", "while", "switch", "guard", "for", "catch", "return", "func", "init", "case", "defer", "do", "else",
            "go", "select"
        ]
        while index < body.count {
            guard isIdentifier(body[index]), index == 0 || !isIdentifier(body[index - 1]) else {
                index += 1
                continue
            }
            var end = index
            while end < body.count, isIdentifier(body[end]) { end += 1 }
            let word = String(String.UnicodeScalarView(body[index ..< end]))
            let after = skipSpace(end, body)
            defer { index = end }
            guard after < body.count, body[after] == "(", !keywords.contains(word) else { continue }
            // The receiver: nothing (unqualified), `self`/`Self`, or something else (skipped).
            var before = index - 1
            while before >= 0, body[before] == " " || body[before] == "\n" || body[before] == "\t" { before -= 1 }
            if before >= 0, body[before] == "." {
                var receiverEnd = before
                var receiverStart = receiverEnd
                while receiverStart > 0, isIdentifier(body[receiverStart - 1]) { receiverStart -= 1 }
                receiverEnd = max(receiverStart, receiverEnd)
                let receiver = String(String.UnicodeScalarView(body[receiverStart ..< before]))
                guard language == .swift, receiver == "self" || receiver == "Self" else { continue }
            }
            let close = closing(of: after, in: body)
            let labels = language == .swift ? callLabels(Array(body[(after + 1) ..< min(close, body.count)])) : []
            found.insert(language == .swift ? "\(word)(\(labels.map { $0 + ":" }.joined()))" : word)
        }
        return found
    }

    /// The external argument labels of a parameter list: `_ a: Int, label b: Int, c: Int` gives `_`, `label`, `c`.
    private static func parameterLabels(_ list: [Unicode.Scalar]) -> [String] {
        splitTopLevel(list)
            .compactMap { parameter in
                let words = String(String.UnicodeScalarView(parameter))
                    .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == ":" }).map(String.init)
                return words.first
            }
    }

    /// The labels of a call's arguments: `f(1, x: 2)` gives `_`, `x`.
    private static func callLabels(_ list: [Unicode.Scalar]) -> [String] {
        splitTopLevel(list)
            .map { argument in
                var cursor = skipSpace(0, argument)
                let start = cursor
                while cursor < argument.count, isIdentifier(argument[cursor]) { cursor += 1 }
                let afterWord = skipSpace(cursor, argument)
                guard cursor > start, afterWord < argument.count, argument[afterWord] == ":" else { return "_" }
                return String(String.UnicodeScalarView(argument[start ..< cursor]))
            }
    }

    private static func splitTopLevel(_ list: [Unicode.Scalar]) -> [[Unicode.Scalar]] {
        var parts: [[Unicode.Scalar]] = []
        var current: [Unicode.Scalar] = []
        var depth = 0
        for scalar in list {
            if "([{<".unicodeScalars.contains(scalar) { depth += 1 }
            if ")]}>".unicodeScalars.contains(scalar), !(scalar == ">" && current.last == "-") { depth -= 1 }
            if scalar == ",", depth == 0 {
                parts.append(current)
                current = []
            } else {
                current.append(scalar)
            }
        }
        if !current.allSatisfy({ $0 == " " || $0 == "\n" }) { parts.append(current) }
        return parts
    }
}
