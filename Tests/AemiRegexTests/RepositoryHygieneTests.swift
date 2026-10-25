import Foundation
import Testing

/// Nothing that must not be published is tracked (see `RepositoryHygiene`). Each rule is broken on purpose below.
struct RepositoryHygieneTests {
    private func problems(_ files: [String: String], sizes: [String: Int] = [:]) -> [String] {
        RepositoryHygiene.problems(paths: files.keys.sorted(), size: { sizes[$0] }, text: { files[$0] })
    }

    @Test func `clean files produce no problems`() {
        #expect(problems(["Sources/A/A.swift": "struct A {}\n", "docs/x.md": "# x\n"]).isEmpty)
    }

    @Test func `build output, system debris and a large binary are reported`() {
        #expect(problems(["Benchmarks/rust/target/release/bench": ""]).count == 1)
        #expect(problems([".build/x": ""]).count == 1)
        #expect(problems(["docs/.DS_Store": ""]).count == 1)
        #expect(problems(["lib.a": ""], sizes: ["lib.a": RepositoryHygiene.maximumBytes + 1]).count == 1)
        #expect(problems(["lib.a": ""], sizes: ["lib.a": RepositoryHygiene.maximumBytes]).isEmpty)
    }

    @Test func `a work marker in a Swift source is reported, and in a document it is not`() {
        #expect(problems(["A.swift": "// " + "TO" + "DO: later"]).count == 1)
        #expect(problems(["B.swift": "let note = \"FIX" + "ME\""]).count == 1)
        #expect(problems(["notes.md": "a TO" + "DO in prose"]).isEmpty)
    }

    @Test func `a home-directory path, a token and a private key are reported`() {
        let home = "/Us" + "ers/someone/Developer"
        #expect(problems(["a.md": "see \(home)/x"]).count == 1)
        #expect(problems(["b.md": "token " + "gh" + "o_abc"]).count == 1)
        #expect(problems(["c.pem": "-----BEGIN " + "PRIVATE KEY-----"]).count == 1)
    }

    @Test func `the repository tracks nothing that must not be published`() {
        let paths = RepositoryHygiene.trackedPaths()
        #expect(paths.count > 100, "git must be available and the scan must see the repository: \(paths.count) paths")
        let root = DocumentationLayout.repositoryRoot
        let found = RepositoryHygiene.problems(
            paths: paths,
            size: {
                (try? FileManager.default.attributesOfItem(atPath: root.appending(path: $0).path)[.size] as? Int) ?? nil
            },
            text: { path in
                guard
                    path.hasSuffix(".swift") || path.hasSuffix(".md") || path.hasSuffix(".go") || path.hasSuffix(".sh")
                        || path.hasSuffix(".yml") || path.hasSuffix(".txt") || path.hasSuffix(".c")
                        || path.hasSuffix(".h")
                        || path.hasSuffix(".json") || path.hasSuffix(".py") || path.hasSuffix(".rs")
                        || path.hasSuffix(".toml")
                else { return nil }
                return try? String(contentsOf: root.appending(path: path), encoding: .utf8)
            })
        #expect(found.isEmpty, "\(found.joined(separator: "\n"))")
    }
}
