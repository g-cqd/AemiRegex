import AemiRegex
import Foundation

/// Searches every file in the corpus repeatedly for `seconds`, so a sampling profiler sees a steady state.
func runLoop(pattern: String, corpusPath: String, seconds: Double) {
    var blobs: [[UInt8]] = []
    if let walker = FileManager.default.enumerator(atPath: corpusPath) {
        for case let path as String in walker where path.hasSuffix(".swift") {
            if let data = FileManager.default.contents(atPath: corpusPath + "/" + path) { blobs.append(Array(data)) }
        }
    }
    guard let compiled = try? Pattern(pattern) else { return }
    let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(seconds * 1e9)
    var total = 0
    while DispatchTime.now().uptimeNanoseconds < deadline {
        total += blobs.reduce(0) { $0 + compiled.matches(in: $1).count }
    }
    print("matches counted: \(total)")
}
