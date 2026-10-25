# AemiRegex

A regular-expression engine for Swift whose search time is proportional to the pattern times the input, for every pattern.
No backtracking, so no pattern can make a search exponential. Zero package dependencies; the engine reads UTF-8 bytes.

**Status.** The RE2 syntax subset works and is checked against Go's `regexp` (and ICU where ICU agrees with RE2). Measured on one corpus
and one machine it is faster than `NSRegularExpression`, Swift `Regex` and Go's `regexp`, and **slower than Rust's `regex` crate on every
per-file workload** (median 2.2x) and than PCRE2 with JIT on most (median 2.2x; it wins five of 14 rows). It is not the fastest engine and
does not claim to be; see `docs/research/engine-comparison-2026-10.md` for the numbers, the causes, the safety nets and the work queue. A
small C target (NEON, SSSE3, scalar) holds the multi-literal prefilter kernel. I-Regexp (RFC 9485) is built, whole-string by default;
`\p{…}` works over general categories and scripts, and `(?i)` folds Unicode. A `String` API, ECMAScript and PCRE2 are not built yet.

```swift
import AemiRegex

let pattern = try Pattern(#"(?P<name>\w+)@(\w+)\.com"#)
let haystack = Array("mail bob@example.com now".utf8)
if let match = pattern.firstMatch(in: haystack) {
    match.range                                   // 5 ..< 20, UTF-8 byte offsets
    match.groups[pattern.groupIndex(named: "name") ?? 0]   // 5 ..< 8
}
let all = pattern.matches(in: haystack)
```

```swift
// I-Regexp (RFC 9485): strictly checked, and a match is the whole string, as the RFC defines it.
let username = try Pattern(#"[a-z][a-z0-9_]*"#, syntax: .iRegexp)
username.firstMatch(in: Array("alice_1".utf8)) != nil      // true
username.firstMatch(in: Array("Alice".utf8)) != nil        // false
try Pattern(#"\d+"#, syntax: .iRegexp)                     // throws: \d is not in I-Regexp, with the offset
```

Not supported, by design: backreferences, lookaround, atomic groups, possessive quantifiers. A pattern that uses them throws
`PatternError.syntax(.unsupported, …)`.

## Develop

```sh
git config core.hooksPath .githooks
swift test -c release --enable-testable-imports        # the suite
AEMIREGEX_DEV=1 swift package --disable-sandbox lint   # the shared lint
Scripts/analyzers.sh                                   # deadwood, dolly, arcleak
Scripts/bench-compare.sh                               # AemiRegex vs ICU, Swift Regex, Go, Rust regex, PCRE2 JIT
Scripts/teddy-check.sh                                 # the C kernel: SIMD vs scalar, ASan+UBSan, and x86_64 under Rosetta
AEMIREGEX_DEV=1 swift run -c release AemiRegexBench <corpus-dir>
go run Scripts/golden/gen.go > Tests/AemiRegexTests/Resources/re2-golden.jsonl   # regenerate the Go oracle fixture
```

Documents: `docs/WHITE-PAPER.md` (the principles), `docs/adr/` (decisions), `docs/roadmap/` (what is owed, in order, with blockers),
`docs/diary/` (the log and the probe ledger), `docs/DESIGN.md` (the architecture as built), `docs/research/` (dated notes with their probes).
`AGENTS.md` is for anyone working in the repository.
