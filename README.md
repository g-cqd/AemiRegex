# AemiRegex

A regular-expression engine for Swift whose search time is proportional to the pattern times the input, for every pattern.
No backtracking, so no pattern can make a search exponential. Zero package dependencies; the engine reads UTF-8 bytes.

**Status.** The RE2 syntax subset works, is checked against Go's `regexp` (and ICU where ICU agrees with RE2), and is faster than
`NSRegularExpression` and Swift `Regex` on every measured workload: 3 to 45x on most, 1.0 to 2.4x on the thinnest (patterns that match
empty and have no literal to skip to). A prefilter, a lazy DFA and a reverse DFA do the work; the Pike VM only fills in captures. Numbers,
caveats and what is not covered: `docs/ROADMAP.md`. Unicode classes and a `String` API are next.

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

Not supported, by design: backreferences, lookaround, atomic groups, possessive quantifiers. A pattern that uses them throws
`PatternError.syntax(.unsupported, …)`.

## Develop

```sh
git config core.hooksPath .githooks
swift test -c release --enable-testable-imports        # the suite
AEMIREGEX_DEV=1 swift package --disable-sandbox lint   # the shared lint
Scripts/analyzers.sh                                   # deadwood, dolly, arcleak
AEMIREGEX_DEV=1 swift run -c release AemiRegexBench <corpus-dir>
go run Scripts/golden/gen.go > Tests/AemiRegexTests/Resources/re2-golden.jsonl   # regenerate the Go oracle fixture
```

Documents: `docs/DESIGN.md` (architecture, semantics, deliberate differences), `docs/ROADMAP.md` (phases, gates, owner questions),
`docs/research/` (probes, with their sources).
