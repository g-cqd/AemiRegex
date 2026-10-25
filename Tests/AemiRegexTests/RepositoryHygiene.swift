import Foundation

/// What must never be tracked or published: build output, large binaries, home-directory paths, and credentials. The rule exists
/// because build output and a personal path were once committed here and found only by a manual search before the first push.
enum RepositoryHygiene {
    static let maximumBytes = 3_000_000
    private static let buildDirectories: Set<String> = ["target", ".build", ".swiftpm", "DerivedData", "node_modules"]
    private static let junkNames: Set<String> = [".DS_Store"]

    /// Patterns are assembled from pieces so that this file does not contain what it forbids.
    private static let forbiddenText: [(label: String, needle: String)] = [
        ("a home-directory path", "/Us" + "ers/"), ("a home-directory path", "/ho" + "me/"),
        ("a GitHub token", "gh" + "o_"), ("a GitHub token", "gh" + "p_"), ("a GitHub token", "github" + "_pat"),
        ("a private key", "BEGIN " + "PRIVATE KEY"), ("a private key", "BEGIN OPENSSH " + "PRIVATE")
    ]

    /// What is wrong with a set of tracked files, one sentence each; empty when they are clean.
    static func problems(paths: [String], size: (String) -> Int?, text: (String) -> String?) -> [String] {
        var problems: [String] = []
        for path in paths {
            let parts = path.split(separator: "/").map(String.init)
            if let bad = parts.first(where: { buildDirectories.contains($0) }) {
                problems.append("\(path): inside \(bad), which is build output")
            }
            if let name = parts.last, junkNames.contains(name) { problems.append("\(path): editor or system debris") }
            if let bytes = size(path), bytes > maximumBytes {
                problems.append("\(path): \(bytes) bytes, over \(maximumBytes)")
            }
            if let content = text(path) {
                for (label, needle) in forbiddenText where content.contains(needle) {
                    problems.append("\(path): contains \(label)")
                }
                // The family's tag check (aemi's check-tags.sh) bans these markers in Swift sources, strings included.
                if path.hasSuffix(".swift"), content.contains("TO" + "DO") || content.contains("FIX" + "ME") {
                    problems.append("\(path): contains a work marker; track work in the roadmap or an issue")
                }
            }
        }
        return problems
    }

    /// The tracked files of the repository, from `git ls-files`; empty when git is unavailable.
    static func trackedPaths() -> [String] {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = ["-C", DocumentationLayout.repositoryRoot.path, "ls-files", "-z"]
        let pipe = Pipe()
        process.standardOutput = pipe
        guard (try? process.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\0").map(String.init)
    }
}
