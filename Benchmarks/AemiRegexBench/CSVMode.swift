import AemiRegex
import Foundation

/// The cross-engine mode: reads `workloads.tsv` and a corpus directory, and prints `engine,workload,median_ms,count` rows in the same
/// format as the Go, Rust and PCRE2 harnesses in `Benchmarks/Comparison`, so one script can put every engine in one table.
func runCSV(workloadsPath: String, corpusPath: String) {
    var paths: [String] = []
    if let walker = FileManager.default.enumerator(atPath: corpusPath) {
        for case let path as String in walker where path.hasSuffix(".swift") { paths.append(path) }
    }
    paths.sort()
    var blobs = paths.compactMap { FileManager.default.contents(atPath: corpusPath + "/" + $0).map { Array($0) } }
    if ProcessInfo.processInfo.environment["CONCAT"] != nil {
        blobs = [Array(blobs.joined())]  // one buffer: measures scan speed without per-call overhead
    }
    let texts = blobs.map { String(decoding: $0, as: UTF8.self) }
    guard let table = try? String(contentsOfFile: workloadsPath, encoding: .utf8) else { return }

    func median(rounds: Int, _ body: () -> Int) -> (Double, Int) {
        var times: [Double] = []
        var count = 0
        for _ in 0 ..< rounds {
            let start = DispatchTime.now().uptimeNanoseconds
            count = body()
            times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
        }
        times.sort()
        return (times[times.count / 2], count)
    }

    for line in table.split(separator: "\n") {
        let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { continue }
        let (name, pattern) = (parts[0], parts[1])
        if let ours = try? Pattern(pattern) {
            let r = median(rounds: 9) { blobs.reduce(0) { $0 + ours.matches(in: $1).count } }
            print("AemiRegex,\(name),\(String(format: "%.2f", r.0)),\(r.1)")
        }
        if let icu = try? NSRegularExpression(pattern: pattern) {
            let r = median(rounds: 9) {
                texts.reduce(0) {
                    $0 + icu.numberOfMatches(in: $1, range: NSRange(location: 0, length: $1.utf16.count))
                }
            }
            print("NSRegularExpression (ICU),\(name),\(String(format: "%.2f", r.0)),\(r.1)")
        }
        if let swiftRegex = try? Regex(pattern) {
            let r = median(rounds: 3) { texts.reduce(0) { $0 + $1.matches(of: swiftRegex).count } }
            print("Swift Regex,\(name),\(String(format: "%.2f", r.0)),\(r.1)")
        }
    }
}
