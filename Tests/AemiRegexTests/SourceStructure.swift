import Foundation

/// The structure rules `ask` gates (its ADR-0021): a file declares one top-level type and is named for it, and no file runs past a line
/// cap, so that the file listing shows the types the project owns and a file stays readable. Generated files are exempt.
enum SourceStructure {
    static let maximumLines = 250

    /// What is wrong with a set of Swift files, one sentence each; empty when they are sound.
    ///
    /// A file is sound when it has at most `maximumLines` lines, declares at most one top-level type (`struct`, `class`, `enum`,
    /// `protocol`, `actor`) whose name is the file's name up to any `+`, and, if it has only extensions, extends one type, named by the
    /// start of the file's name (`Outer.Inner` as `Outer+Inner`).
    static func problems(in files: [(name: String, text: String)]) -> [String] {
        var problems: [String] = []
        for file in files where !file.name.hasPrefix("Generated") {
            let lines = file.text.split(separator: "\n", omittingEmptySubsequences: false).count - 1
            if lines > maximumLines { problems.append("\(file.name): \(lines) lines, over \(maximumLines)") }
            let stem = String(file.name.dropLast(6))
            let owner = String(stem.split(separator: "+", omittingEmptySubsequences: false).first ?? "")
            let (types, extensions) = declarations(in: file.text)
            if types.count > 1 {
                problems.append(
                    "\(file.name): declares \(types.count) top-level types (\(types.joined(separator: ", ")))")
            } else if let type = types.first, type != owner {
                problems.append(
                    "\(file.name): declares \(type), so the file should be named \(type).swift or \(type)+….swift")
            } else if types.isEmpty, let first = extensions.first {
                if Set(extensions).count > 1 {
                    problems.append(
                        "\(file.name): extends several types (\(Set(extensions).sorted().joined(separator: ", ")))")
                } else {
                    // `extension Outer.Inner` lives in `Outer+Inner.swift` or `Outer+Inner+Feature.swift`.
                    let expected = first.replacingOccurrences(of: ".", with: "+")
                    if stem != expected, !stem.hasPrefix(expected + "+") {
                        problems.append(
                            "\(file.name): extends \(first), so the file should be named \(expected)+….swift")
                    }
                }
            }
        }
        return problems
    }

    /// The names of the top-level types and the types extended at the top level of `text`, in order.
    static func declarations(in text: String) -> (types: [String], extensions: [String]) {
        var types: [String] = []
        var extensions: [String] = []
        let keywords: Set<String> = ["struct", "class", "enum", "protocol", "actor"]
        let modifiers: Set<String> = [
            "public", "internal", "private", "fileprivate", "final", "indirect", "package", "open"
        ]
        for line in RecursionScan.blank(text, language: .swift).split(separator: "\n", omittingEmptySubsequences: false)
        {
            guard let first = line.first, first != " ", first != "\t", first != "}", first != "/" else { continue }
            var words = line.split(whereSeparator: { $0 == " " || $0 == "(" || $0 == ":" || $0 == "{" || $0 == "<" })
                .map(String.init)
            while let head = words.first, head.hasPrefix("@") || modifiers.contains(head) { words.removeFirst() }
            guard words.count >= 2 else { continue }
            if keywords.contains(words[0]) {
                types.append(words[1])
            } else if words[0] == "extension" {
                extensions.append(words[1])
            }
        }
        return (types, extensions)
    }
}
