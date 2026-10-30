# Whole matches and short inputs — 2026-10-30

Read while extracting swift-search from SwiftStaticAnalysis, which matches user patterns against declaration names: one compiled pattern,
hundreds of thousands of short identifiers. The same use is coming from deadwood (`SafeRegex`, `RegexCache`, analyzerkit P9).

## `wholeMatch(in:)` misses whole matches

`Pattern.wholeMatch(in:)` and `BacktrackingPattern.wholeMatch(in:)` take the leftmost-first match and keep it only if it spans the text.
Leftmost-first is not leftmost-longest, so a pattern whose preferred branch is a prefix of another misses:

| Call | AemiRegex | Swift `Regex`, RE2 `FullMatch` |
|---|---|---|
| `Pattern("a\|ab").wholeMatch(in: "ab")` | `nil` | `0..<2` |
| `Pattern("a\|ab", syntax: .re2, matching: .wholeString).firstMatch(in: "ab")` | `0..<2` | — |
| `Pattern("(?:a\|ab)(?:c\|bcd)").wholeMatch(in: "abcd")` | `0..<4` (by luck: the first path spans) | `0..<4` |

On failure the method also scans the whole text for a match that can only be rejected. `.wholeString` is right: the parser wraps the code
in `beginText`/`endText`, so the automaton itself requires both edges.

Fix: `wholeMatch` runs a whole-string twin of the program, compiled on first use from the same source and limits and kept in a lock-guarded
box shared by copies of the pattern; a pattern compiled `.wholeString` is its own twin. The backtracker gets a run-time mode instead (start
only at 0; a `match` instruction away from the end fails and backtracks), so no second program is built.

## Short inputs pay a constant

Probe `probes/whole-match-and-short-inputs.swift.txt`, 200,000 generated identifiers of three words each, release, best of five, per name:

| Method | ns |
|---|---:|
| `^(?:load.*)$` `isMatch` | 154 |
| `load.*` compiled `.wholeString`, `isMatch` | 151 |
| `load.*` `wholeMatch(in:)` | 202 |
| Swift `Regex.wholeMatch` | 406 |
| `hasPrefix("load")`, the floor | 67 |
| `^(?:.*Value.*)$` `isMatch` | 181 |

Compiling `^(?:loadN.*)$` takes about 28 µs. About 85 ns of every call is not matching: the scratch pool checkout, the
contiguous-storage closure, the search setup. On a 20-byte name that is more than the scan. Entry 0017 measures the split and removes what it
can (a pool fast path for one thread, a direct path for a native `String`, a start state built once per pattern).

## Required literals

Index queries (swift-search H4) and trigram prefilters want to know which literals every match contains, to skip candidates before running
the automaton. The prefilter and `LiteralSet` analysis already compute a part of this, internally. Entry 0016 makes it public as
`Pattern.requiredLiterals`: a set of byte strings such that every match contains at least one, or `nil` when no useful set exists.
