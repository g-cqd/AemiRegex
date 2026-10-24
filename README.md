# AemiRegex

A regular-expression engine for Swift whose search time is proportional to the pattern times the input, for every pattern.
No backtracking, so no pattern can make a search exponential. Zero package dependencies; the engine reads UTF-8 bytes.

**Status: Phase 1.** The RE2 syntax subset works and is checked against Go's `regexp` and ICU. It is not yet faster than
`NSRegularExpression` on literal-heavy searches; see `docs/ROADMAP.md` for the measured numbers and the plan.

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
