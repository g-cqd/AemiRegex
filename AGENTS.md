# Working in `aemiregex`

A linear-time regex engine for Swift. **Read [`docs/WHITE-PAPER.md`](docs/WHITE-PAPER.md) first**: it carries the principles, and leads
with the evidence rule. This file records what an agent cannot derive from the source: commands, gates, traps and the state of the work.

## Commands

```sh
swift test -c release --enable-testable-imports          # the suite, in release (what ships); ~3 s
AEMIREGEX_DEV=1 swift test                               # debug: assertions and bounds checks on unsafe pointers are live
swift test --sanitize=address --sanitize=undefined --enable-testable-imports
swift test --sanitize=thread --enable-testable-imports
AEMIREGEX_DEV=1 swift package --disable-sandbox lint     # the shared Aemi lint; also the pre-commit hook's formatter
Scripts/analyzers.sh                                     # deadwood, dolly, arcleak, pinned by version and SHA-256
Scripts/teddy-check.sh                                   # the C kernel: SIMD vs scalar, ASan+UBSan, x86_64 under Rosetta
Scripts/bench-compare.sh                                 # AemiRegex vs ICU, Swift Regex, Go, Rust regex, PCRE2 JIT (frozen corpus)
go run Scripts/golden/gen.go > Tests/AemiRegexTests/Resources/re2-golden.jsonl            # regenerate the Go oracle fixtures
go run Scripts/golden/generated/gen.go > Tests/AemiRegexTests/Resources/re2-generated.jsonl
go run Scripts/golden/iregexp/gen.go Tests/AemiRegexTests/Resources                      # the I-Regexp fixtures (grammar and golden)
go run Scripts/unicode/gen.go > Sources/AemiRegex/Syntax/GeneratedUnicodeTables.swift    # Unicode tables; the output is already formatted
git config core.hooksPath .githooks                      # once per clone: pre-commit lint, pre-push release run
```

Build and test in **release**. A debug build measures a program nobody ships, but the debug run is also a safety net (see Traps).

## Gates

`DocumentationLayoutTests` (documents), `NoRecursionTests` (ADR-0003, a heuristic scan of Swift and Go), `SourceStructureTests` (ADR-0010: one type per file, 250 lines), `RepositoryHygieneTests` (no build output, large file, home-directory path or token is tracked), `GoldenTests` and `GeneratedGoldenTests` (Go as oracle), `BacktrackOracleTests` (`node` and `libpcre2` as oracles for `BacktrackingPattern`; fixtures from `Scripts/oracle/`), `DifferentialTests` (ICU, assertion-free
patterns only), `EngineAgreementTests` and `MalformedInputTests` (the DFA pipeline against the Pike VM, which indexes with checks),
`SpeedGateTests` (release only: faster than ICU on each workload with equal match counts), `ByteScanTests` and `TeddyTests` (poisoned
tails, guard bands, dense candidates). The analyzers run under `--strict`: fix a finding, or accept it where it is with a reason
(`// @dl:accept -- why`, on the line directly above the anchor).

## Traps

- **A test that passes on the wrong engine.** Engines give the same answers, so a result cannot show which one ran. `Pattern.searchCounts`
  can. A new fast path needs a test that asserts it was taken.
- **Python edits that miss silently.** `swift format` rewraps signatures, so a `str.replace` anchored on a one-line signature can match
  nothing and the script still "succeeds". Grep for the result of every scripted edit.
- **A tolerance in a conformance test hides bugs.** The oracle suite once allowed 20% skipped cases; a missing `NOTEMPTY_ATSTART` made every
  global PCRE2 search run out of budget, were skipped, and the suite passed. Budget skips now fail the test.
- **Mutation scripts must fail loudly.** A `str.replace` that matches nothing leaves the code unchanged; assert the anchor is present.
- **`node` has bugs.** `/[^a]$/u` finds nothing on a text that ends in an astral character (node 26.12.1), and V8 can start a match inside a
  surrogate pair. The fixture script drops the second kind and counts it; the first is reported in the diary.
- **Never `git checkout <file>` to undo a mutation.** It restores the last commit and discards uncommitted edits. Copy first, restore the copy.
- **`sample` is shadowed by a Python script on this machine's PATH.** Use `/usr/bin/sample`. Half the samples are the idle thread
  (`__workq_kernreturn`); read the rest as 100%.
- **An overread by one byte inside an allocation changes no answer.** Release tests cannot see it. Debug builds (bounds-checked
  `UnsafeBufferPointer`), ASan, and poisoned-tail tests can. Run all three after touching `Scan/` or `LazyDFA`.
- **The corpus moves.** The published numbers used a snapshot of `ask/Sources` (a live repository, not part of this one):
  `Scripts/bench-compare.sh <dir>` snapshots a directory first; compare numbers only from one run, and only on one corpus.
- **`@testable` needs `--enable-testable-imports` in release** (same as `ask`, ADR-0006 there).
- **`Array.span` needs macOS 26.** The floor is 15, so the core takes `UnsafeBufferPointer` inside the module.
- **Another writer may share the working tree.** Check `git status` for changes you did not make; do not `git add -A` under them.

## Dependencies

None for the engine. `CAemiRegex` is the one C target (ADR-0004). Dev tooling comes from Aemi at a pinned revision under
`AEMIREGEX_DEV=1` only, so consumers never resolve it.

## Commit discipline

Atomic and buildable. The message states why. Never mix a refactor and a behaviour change. Slice by behaviour, not by file type.

## Current state

Phases and their order are in `docs/roadmap/`; read an entry's `status:` and `blocked-by:` before starting it. The order the owner set is
I-Regexp (0004, done), Unicode (0005, done), then the Rust gap (0006); ECMAScript, PCRE2 and the budgeted backtracking engine follow Unicode.
Built: RE2 syntax, I-Regexp with whole-string matching, `\p` over categories and scripts, and Unicode simple case folding, all from generated
tables (ADR-0009; Go's Unicode 17.0.0); a `String` API; CI (green on Linux and macOS); and `BacktrackingPattern` (ADR-0011) for ECMAScript and
PCRE2, checked against `node` and `libpcre2`. Completed: RE2, I-Regexp, Unicode (properties, fold), ECMAScript (u/v flags, properties, repeated names), PCRE2 (subroutines, conditionals, flags),
Backtracker (ADR-0011), String/Substring API (0011), CI gates (0012), and AemiJSON migration (0013).
Rust performance tracking is paused by owner direction (0006); preserve its measurements and untested hypotheses in
`docs/research/engine-comparison-2026-10-25.md` and the roadmap, without scheduling comparison runs. Native x86_64 timing (0014) remains unavailable.
