---
status: accepted
supersedes: ADR-0008
date: 2026-10-25
---

# 0009 — Unicode data is generated from one source

## Context

ADR-0008 took general categories from the standard library as an interim source. Roadmap 0005 had to add scripts and Unicode case
folding, which the standard library cannot supply, so the question became whether to mix sources or use one.

## The probes (Go 1.27.3 and the Swift 6.4 standard library, both Unicode 17.0.0)

- **Categories:** the standard library and Go agree on all 1,114,112 scalar values (0 mismatches).
- **Fold orbits derived from the standard library's lower and upper mappings:** 38.8 ms to build, and wrong in 5 of Go's 1,482 orbits.
  It merges U+0131 `ı` into {I, i} (a Turkic mapping, not a simple folding) and misses {U+0390, U+1FD3}, {U+03B0, U+1FE3} and
  {U+FB05, U+FB06}, which exist only as simple folding entries.
- **Scripts:** not in the standard library: 174 scripts, 948 table ranges in Go.
- **Go 1.27 is not RE2 any more, and the ADRs that said so were stale.** It matches property names loosely (case, spaces,
  underscores and hyphens ignored), accepts `Any`, `Assigned`, `Ascii`, `Lc`, 42 long-name category aliases, and has `Cn`; its `C` is
  `Cc Cf Co Cs Cn`, which includes unassigned code points, exactly XSD's reading. The two readings of `C` that ADR-0008 and the I-Regexp
  tests described no longer differ, so the switch for them is gone.
- **Swift's Unicode data ships with the OS.** On an older macOS the standard library's categories could be at an older Unicode version
  than generated scripts and folding.

## Decision

`Scripts/unicode/gen.go` generates `GeneratedUnicodeTables.swift` from Go's `unicode` package: the 29 two-letter categories, scripts,
category aliases and fold orbits, one Unicode version, written in the file. `Cn`, the one-letter groups, `C` and `LC` are derived in Swift,
and the generator fails if Go's own tables disagree with those rules. Property names are resolved as Go resolves them
(`UnicodeProperties`). A class is case-folded first and negated after, as Go does, so `(?i)\W` leaves out `ſ` and the Kelvin sign. The
generator's output is already formatted, so CI regenerates it and diffs.

## Evidence (release, Apple M2 Pro)

- Cold `\p{L}`: 0.85 ms (ADR-0008's scan: 46.6 ms). `\p{Greek}`: 0.19 ms, 197 instructions. A `(?i)` literal: 50 to 70 microseconds.
- 142 patterns x 40 haystacks agree with Go, including `(?i)` over Unicode, folded classes and negated classes, loose names and aliases.
- Six mutations (folding adds nothing; negate before fold; only the first letter of a name normalised; `Cn` forgetting a category;
  the orbit search skipping an entry; `Lc` without titlecase) each turn the suite red.
- The categories are also compared with the standard library for every character assigned before Unicode 15, on whatever platform runs the
  tests, so a table that drifts from the platform's data is noticed.

## Consequences

The data is Go's Unicode version, not the platform's, and moves when the generator is rerun. About 1,700 generated lines (130 KB) are in
the repository. `AemiUnicode` remains the better home for these tables if a second consumer appears (roadmap 0005 notes it); promoting them
is a change to a shared package. Not covered: binary properties and `Script_Extensions` (ECMAScript, roadmap 0007), and Unicode word
boundaries. ECMAScript and PCRE2 fold differently from RE2 (JavaScript canonicalises through upper-casing without the simple folding of
non-ASCII to ASCII; PCRE folds ASCII only unless told otherwise), so this folding is RE2's and the others bring their own.
