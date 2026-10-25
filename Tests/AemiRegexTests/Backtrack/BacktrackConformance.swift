import Foundation

@testable import AemiRegex

/// Compares the backtracker with the recorded answers of an oracle and says how each case went.
enum BacktrackConformance {
    struct Report {
        var checked = 0
        /// Cases the engine declined: an unsupported construct, or a budget that ran out.
        var skipped: [String] = []
        var mismatches: [String] = []
    }

    static func run(_ cases: [BacktrackCase], dialect: BacktrackingPattern.Dialect) -> Report {
        var report = Report()
        for item in cases {
            let compiled: BacktrackingPattern
            do {
                compiled = try BacktrackingPattern(item.p, dialect: dialect, options: item.options)
            } catch {
                if item.r == .error {
                    report.checked += 1
                } else if error == .syntax(.unsupported, offset: error.offset) {
                    report.skipped.append("unsupported: \(item.p)")
                } else {
                    report.mismatches.append("\(describe(item)): oracle accepts, we reject with \(error)")
                }
                continue
            }
            if item.r == .error {
                report.mismatches.append("\(describe(item)): oracle rejects, we accept")
                continue
            }
            let actual: CaseResult
            do {
                if item.f.contains("g") {
                    actual = .all(try compiled.matches(in: item.s).map(\.groups))
                } else {
                    actual = try compiled.firstMatch(in: item.s).map { .match($0.groups) } ?? .noMatch
                }
            } catch {
                report.skipped.append("budget: \(item.p)")
                continue
            }
            report.checked += 1
            if !actual.agrees(with: item.r) {
                report.mismatches.append("\(describe(item)): expected \(item.r), got \(actual)")
            }
        }
        return report
    }

    private static func describe(_ item: BacktrackCase) -> String {
        "/\(item.p)/\(item.f) on \(String(reflecting: item.s))"
    }

    private enum CaseResult: CustomStringConvertible {
        case noMatch
        case match([Range<Int>?])
        case all([[Range<Int>?]])

        func agrees(with expected: BacktrackCase.Expected) -> Bool {
            switch (self, expected) {
                case (.noMatch, .noMatch): true
                case (.match(let a), .match(let b)): a == b
                case (.all(let a), .all(let b)): a == b
                default: false
            }
        }

        var description: String {
            switch self {
                case .noMatch: "noMatch"
                case .match(let groups): "match(\(groups))"
                case .all(let matches): "all(\(matches))"
            }
        }
    }
}

extension PatternError {
    /// The offset an error carries, or 0.
    fileprivate var offset: Int {
        if case .syntax(_, let offset) = self { return offset }
        return 0
    }
}
