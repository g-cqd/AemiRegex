# AemiRegex

Linear-time regular-expression engine for Swift 6 with no backtracking (`O(pattern × input)` worst-case search time). Supports RE2 syntax and RFC 9485 I-Regexp over UTF-8 bytes with SIMD multi-literal prefiltering, lazy DFA execution, PikeVM capture extraction, and Unicode general categories/scripts.

```swift
import AemiRegex

let pattern = try Pattern(#"[A-Z][a-z]+-\d+"#)
if let match = pattern.firstMatch(in: "Issue Core-42 opened") {
    print(match.range)
}
```

## Requirements

- Swift 6.4+ (Swift 6 language mode)
- macOS 15+, iOS 18+, tvOS 18+, watchOS 11+, visionOS 2+, or Linux

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/g-cqd/AemiRegex.git", branch: "main")
]
```

## Documentation

- [Architecture Decisions](docs/adr/)
- [Contributing](CONTRIBUTING.md)
- [Security](SECURITY.md)

## License

[MIT](LICENSE)
