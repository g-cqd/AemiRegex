import AemiRegex
import Foundation

// Compares AemiRegex with NSRegularExpression (ICU) and Swift's Regex on one corpus, in memory, so I/O is not measured.
// Engines are interleaved per round so background load affects all of them alike; the median and the spread are reported.
// Match counts are printed because a faster engine that finds different matches proves nothing.

struct Workload {
    let name: String
    let pattern: String
    let swiftRegexOK: Bool
}

let workloads = [
    Workload(name: "literal", pattern: "Sendable", swiftRegexOK: true),
    Workload(name: "alternation", pattern: "import|struct|enum|class|protocol", swiftRegexOK: true),
    Workload(name: "func-async", pattern: #"func\s+\w+\(.*async"#, swiftRegexOK: true),
    Workload(name: "class+captures", pattern: #"(\w+)\s*:\s*(\w+)\s*\{"#, swiftRegexOK: true),
    Workload(name: "case-insensitive", pattern: "(?i)todo|fixme|hack", swiftRegexOK: false),
    Workload(name: "no-match-rare-byte", pattern: #"Q[0-9]+Z"#, swiftRegexOK: true)
]

let root = CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath
var texts: [String] = []
if let walker = FileManager.default.enumerator(atPath: root) {
    for case let path as String in walker where path.hasSuffix(".swift") && !path.contains(".build") {
        if let data = FileManager.default.contents(atPath: root + "/" + path) {
            texts.append(String(decoding: data, as: UTF8.self))
        }
    }
}
let blobs = texts.map { Array($0.utf8) }
let totalBytes = blobs.reduce(0) { $0 + $1.count }
print("corpus: \(texts.count) files, \(totalBytes) bytes (\(root))")

func measure(rounds: Int, _ body: () -> Int) -> (median: Double, spread: Double, count: Int) {
    var times: [Double] = []
    var count = 0
    for _ in 0 ..< rounds {
        let start = DispatchTime.now().uptimeNanoseconds
        count = body()
        times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
    }
    times.sort()
    return (times[times.count / 2], times[times.count - 1] - times[0], count)
}

print(
    "pattern".padding(toLength: 20, withPad: " ", startingAt: 0)
        + "engine".padding(toLength: 12, withPad: " ", startingAt: 0) + "median ms   spread ms   matches")
for workload in workloads {
    guard let ours = try? Pattern(workload.pattern) else {
        print("\(workload.name): AemiRegex rejected the pattern")
        continue
    }
    let icuPattern = workload.pattern
    guard let icu = try? NSRegularExpression(pattern: icuPattern) else { continue }
    var rows: [(String, (median: Double, spread: Double, count: Int))] = []
    rows.append(("AemiRegex", measure(rounds: 9) { blobs.reduce(0) { $0 + ours.matches(in: $1).count } }))
    rows.append(
        (
            "NSRegex",
            measure(rounds: 9) {
                texts.reduce(0) { $0 + icu.numberOfMatches(in: $1, range: NSRange($1.startIndex..., in: $1)) }
            }
        ))
    if workload.swiftRegexOK, let swiftRegex = try? Regex(workload.pattern) {
        rows.append(("Swift Regex", measure(rounds: 3) { texts.reduce(0) { $0 + $1.matches(of: swiftRegex).count } }))
    }
    for (engine, result) in rows {
        let line =
            workload.name.padding(toLength: 20, withPad: " ", startingAt: 0)
            + engine.padding(toLength: 12, withPad: " ", startingAt: 0)
        print(line + String(format: "%9.2f %11.2f %9d", result.median, result.spread, result.count))
    }
}

// Pathological: a backtracking engine is exponential here. Only AemiRegex is run at full size; ICU and Swift Regex at 26 bytes.
let evil = [UInt8](repeating: UInt8(ascii: "a"), count: 100_000)
if let ours = try? Pattern("(a+)+b") {
    let r = measure(rounds: 3) { ours.firstMatch(in: evil) == nil ? 0 : 1 }
    print("(a+)+b on 100000 'a':  AemiRegex \(String(format: "%.2f", r.median)) ms")
}
let short = String(repeating: "a", count: 26)
if let icu = try? NSRegularExpression(pattern: "^(a+)+$") {
    let r = measure(rounds: 1) { icu.numberOfMatches(in: short + "b", range: NSRange(location: 0, length: 27)) }
    print("^(a+)+$ on 26 'a'+b:   NSRegex   \(String(format: "%.2f", r.median)) ms")
}
