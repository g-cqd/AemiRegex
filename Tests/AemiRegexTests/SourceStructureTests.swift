import Foundation
import Testing

/// One top-level type per file, named for it, and a line cap (the rules of `ask`'s ADR-0021). Each rule is broken on purpose below.
struct SourceStructureTests {
    private func file(_ name: String, _ text: String) -> [(name: String, text: String)] { [(name, text)] }

    @Test func `a file with one type, named for it, is sound`() {
        #expect(SourceStructure.problems(in: file("Box.swift", "struct Box {\n    struct Inner {}\n}\n")).isEmpty)
        #expect(SourceStructure.problems(in: file("Box+Sendable.swift", "extension Box: Sendable {}\n")).isEmpty)
        #expect(
            SourceStructure.problems(in: file("Box+More.swift", "extension Box {}\nextension Box: Equatable {}\n"))
                .isEmpty)
        #expect(SourceStructure.problems(in: file("Fixture.swift", "public final class Fixture {}\n")).isEmpty)
        #expect(SourceStructure.problems(in: file("Outer+Inner+Feature.swift", "extension Outer.Inner {}\n")).isEmpty)
        #expect(SourceStructure.problems(in: file("Outer+Inner.swift", "extension Outer.Inner {}\n")).isEmpty)
    }

    @Test func `two top-level types in one file are reported`() {
        let problems = SourceStructure.problems(in: file("Pair.swift", "struct Pair {}\nenum Mode {}\n"))
        #expect(problems.count == 1)
        #expect(problems.first?.contains("2 top-level types") == true)
    }

    @Test func `a file named for another type is reported`() {
        #expect(SourceStructure.problems(in: file("Wrong.swift", "struct Right {}\n")).count == 1)
        #expect(SourceStructure.problems(in: file("Wrong+More.swift", "extension Right {}\n")).count == 1)
        #expect(SourceStructure.problems(in: file("Mixed+More.swift", "extension A {}\nextension B {}\n")).count == 1)
        #expect(SourceStructure.problems(in: file("Outer+Feature.swift", "extension Outer.Inner {}\n")).count == 1)
        #expect(SourceStructure.problems(in: file("Inner+Feature.swift", "extension Outer.Inner {}\n")).count == 1)
    }

    @Test func `a file over the line cap is reported, and one exactly at it is not`() {
        let at = "struct Long {}\n" + String(repeating: "// x\n", count: SourceStructure.maximumLines - 1)
        #expect(SourceStructure.problems(in: file("Long.swift", at)).isEmpty)
        #expect(SourceStructure.problems(in: file("Long.swift", at + "// x\n")).count == 1)
    }

    @Test func `a generated file is exempt, and a type named in a comment or a string is not a declaration`() {
        let big = "enum GeneratedTables {}\n" + String(repeating: "// x\n", count: 400)
        #expect(SourceStructure.problems(in: file("GeneratedTables.swift", big)).isEmpty)
        let quiet = "struct Quiet {\n    let text = \"struct Other {}\"\n}\n// struct Another {}\n"
        #expect(SourceStructure.problems(in: file("Quiet.swift", quiet)).isEmpty)
    }

    // MARK: This repository

    @Test func `every Swift file in Sources and Tests is within the structure rules`() {
        var files: [(name: String, text: String)] = []
        var pending = ["Sources", "Tests"].map { DocumentationLayout.repositoryRoot.appending(path: $0) }
        while let directory = pending.popLast() {
            let entries =
                (try? FileManager.default.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
            for entry in entries {
                if (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    pending.append(entry)
                } else if entry.pathExtension == "swift", let text = try? String(contentsOf: entry, encoding: .utf8) {
                    files.append((entry.lastPathComponent, text))
                }
            }
        }
        #expect(files.count > 60, "the scan must see the repository: \(files.count) files")
        let problems = SourceStructure.problems(in: files.sorted { $0.name < $1.name })
        #expect(problems.isEmpty, "\(problems.joined(separator: "\n"))")
    }
}
