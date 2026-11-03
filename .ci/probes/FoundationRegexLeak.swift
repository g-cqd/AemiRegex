import Foundation

// Swift 6.4.1 Linux Foundation leaks the UTF-16 pattern buffer for long patterns.
// swiftc -g -sanitize=address FoundationRegexLeak.swift -o /tmp/regex-probe
// /tmp/regex-probe  -> 600 bytes in 1 allocation at _CFRegularExpressionCreate.
let regex = try NSRegularExpression(pattern: String(repeating: "a", count: 300))
_ = regex.firstMatch(in: "a", range: NSRange(location: 0, length: 1))
