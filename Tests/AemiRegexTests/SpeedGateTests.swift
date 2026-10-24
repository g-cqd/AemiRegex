import Foundation
import Testing

@testable import AemiRegex

/// The gate from the roadmap: on each workload AemiRegex is faster than NSRegularExpression (ICU), with the same matches.
/// Release only: a debug build measures a program nobody ships. Rounds are interleaved so background load hits both engines alike,
/// and the comparison uses medians.
struct SpeedGateTests {
    struct Workload: Sendable, CustomTestStringConvertible {
        let name: String
        let pattern: String
        var testDescription: String { name }
    }

    static let workloads = [
        Workload(name: "literal", pattern: "Sendable"),
        Workload(name: "alternation", pattern: "import|struct|enum|class|protocol"),
        Workload(name: "func-async", pattern: #"func\s+\w+\(.*async"#),
        Workload(name: "captures", pattern: #"(\w+)\s*:\s*(\w+)\s*\{"#),
        Workload(name: "case-insensitive", pattern: "(?i)todo|fixme|hack"),
        Workload(name: "no-match-rare-byte", pattern: #"Q[0-9]+Z"#),
        Workload(name: "word-boundary", pattern: #"\bclass\b"#),
        Workload(name: "line-anchor", pattern: #"(?m)^import \w+$"#),
        // These can match empty. The patterns are chosen so that ICU and RE2 count the same matches: they differ on an empty
        // match that touches a non-empty one, and neither pattern has any.
        Workload(name: "empty-word-edges", pattern: #"\b"#),
        Workload(name: "empty-line-ends", pattern: "(?m)$")
    ]

    #if DEBUG
        static let isRelease = false
    #else
        static let isRelease = true
    #endif

    private static let files = SyntheticCorpus.files()
    private static let strings = files.map { String(decoding: $0, as: UTF8.self) }

    private static func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }

    @Test(.enabled(if: isRelease, "timing is only meaningful in a release build"), arguments: workloads)
    func `AemiRegex is faster than NSRegularExpression and finds the same matches`(workload: Workload) throws {
        let ours = try Pattern(workload.pattern)
        let icu = try NSRegularExpression(pattern: workload.pattern)
        var oursTimes: [Double] = []
        var icuTimes: [Double] = []
        var oursCount = 0
        var icuCount = 0
        for _ in 0 ..< 11 {
            var start = DispatchTime.now().uptimeNanoseconds
            oursCount = Self.files.reduce(0) { $0 + ours.matches(in: $1).count }
            oursTimes.append(Double(DispatchTime.now().uptimeNanoseconds - start))
            start = DispatchTime.now().uptimeNanoseconds
            icuCount = Self.strings.reduce(0) {
                $0 + icu.numberOfMatches(in: $1, range: NSRange(location: 0, length: $1.utf16.count))
            }
            icuTimes.append(Double(DispatchTime.now().uptimeNanoseconds - start))
        }
        #expect(oursCount == icuCount, "different matches make the timing meaningless")
        let (mine, theirs) = (Self.median(oursTimes), Self.median(icuTimes))
        #expect(mine < theirs, "\(workload.name): AemiRegex \(mine / 1e6) ms, ICU \(theirs / 1e6) ms")
    }
}
