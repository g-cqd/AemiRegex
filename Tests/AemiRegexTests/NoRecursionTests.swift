import Foundation
import Testing

/// ADR-0003: no function reaches itself, in the library, the tests, the benchmarks or the scripts. The scanner is a heuristic
/// (`RecursionScan`); each rule below is broken on purpose so that it is known to fire.
struct NoRecursionTests {
    private func swift(_ text: String) -> [(name: String, text: String)] { [("fixture.swift", text)] }

    @Test func `a function that calls itself is found`() {
        let found = RecursionScan.findings(
            swift: swift("func countdown(_ n: Int) -> Int { n == 0 ? 0 : countdown(n - 1) }"), go: [])
        #expect(found.count == 1)
        #expect(found.first?.contains("countdown(_:)") == true)
    }

    @Test func `two functions that call each other are found`() {
        let source = """
            func even(_ n: Int) -> Bool { n == 0 ? true : odd(n - 1) }
            func odd(_ n: Int) -> Bool { n == 0 ? false : even(n - 1) }
            """
        #expect(RecursionScan.findings(swift: swift(source), go: []).count == 1)
    }

    @Test func `a method that calls itself through self is found`() {
        let source = """
            struct Tree {
                func depth(of node: Int) -> Int { node == 0 ? 0 : 1 + self.depth(of: node - 1) }
            }
            """
        #expect(RecursionScan.findings(swift: swift(source), go: []).count == 1)
    }

    @Test func `an overload with other labels is not a recursion`() {
        let source = """
            func find(of byte: UInt8, in bytes: [UInt8]) -> Int? { find(ofAny: [byte], in: bytes) }
            func find(ofAny set: [UInt8], in bytes: [UInt8]) -> Int? { bytes.firstIndex(where: { set.contains($0) }) }
            """
        #expect(RecursionScan.findings(swift: swift(source), go: []).isEmpty)
    }

    @Test func `a call through another receiver is not taken for the function of the same name`() {
        let source = """
            struct Branch {
                mutating func append(_ atom: [Int]) { atoms.append(atom.count) }
            }
            """
        #expect(RecursionScan.findings(swift: swift(source), go: []).isEmpty)
    }

    @Test func `a recursion inside a string or a comment is not a recursion`() {
        let source = """
            func quiet(_ n: Int) -> Int {
                // quiet(n - 1) would recurse
                let text = "quiet(n - 1)"
                return text.count
            }
            """
        #expect(RecursionScan.findings(swift: swift(source), go: []).isEmpty)
    }

    @Test func `a Go function that calls itself is found, and a method call is not`() {
        let recursive = "package main\nfunc walk(n int) int {\n\tif n == 0 { return 0 }\n\treturn walk(n - 1)\n}\n"
        #expect(RecursionScan.findings(swift: [], go: [("a.go", recursive)]).count == 1)
        let fine =
            "package main\nfunc (b *B) add(n int) { b.items = append(b.items, n); b.other.add(n) }\nfunc add(n int) {}\n"
        #expect(RecursionScan.findings(swift: [], go: [("b.go", fine)]).isEmpty)
    }

    // MARK: This repository

    private static func sources(extension ext: String) -> [(name: String, text: String)] {
        var found: [(String, String)] = []
        var pending = ["Sources", "Tests", "Benchmarks", "Scripts"]
            .map { DocumentationLayout.repositoryRoot.appending(path: $0) }
        while let directory = pending.popLast() {
            let entries =
                (try? FileManager.default.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
            for entry in entries {
                if entry.lastPathComponent == ".build" { continue }
                if (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    pending.append(entry)
                } else if entry.pathExtension == ext, let text = try? String(contentsOf: entry, encoding: .utf8) {
                    found.append((entry.lastPathComponent, text))
                }
            }
        }
        return found.sorted { $0.0 < $1.0 }
    }

    @Test func `no function in the library, the tests, the benchmarks or the scripts reaches itself`() {
        let swift = Self.sources(extension: "swift")
        let go = Self.sources(extension: "go")
        #expect(
            swift.count > 40 && go.count >= 3,
            "the scan must see the repository: \(swift.count) Swift files, \(go.count) Go files")
        let found = RecursionScan.findings(swift: swift, go: go)
        #expect(found.isEmpty, "\(found.joined(separator: "\n"))")
    }
}
