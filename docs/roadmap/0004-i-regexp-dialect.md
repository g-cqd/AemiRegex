---
status: in-progress
blocked-by: []
date: 2026-10-25
---

# 0004 — The I-Regexp dialect (RFC 9485)

The owner's first dialect after RE2. RFC 9485 defines a small, interoperable regex: `.`, `|`, groups, `* + ? {n,m}` (no lazy forms), bracket
classes, the escapes `\( \) \* \+ \- \. \? \[ \\ \] \^ \n \r \t \{ \| \}`, and `\p{…}` / `\P{…}` over the Unicode **general categories**. `^`
and `$` are ordinary characters, `.` excludes `\n` and `\r`, and nothing outside the grammar is allowed.

## Scope

1. A strict validator: exactly the RFC's ABNF, with the offset of the first violation. Oracle: an independent recogniser written from the
   RFC text in Go (`Scripts/golden/iregexp/`), run on generated strings; both sides must accept and reject the same set.
2. Matching: translate to the RE2 machinery (`.` becomes `[^\n\r]`, normal characters are escaped, groups do not capture) and check
   against Go on generated patterns and haystacks.
3. General categories for `\p{…}`. Interim source: the Swift standard library (`Unicode.Scalar.Properties.generalCategory`), scanned once
   and cached, so the platform's Unicode version decides category membership. Roadmap 0005 replaces it with generated tables if the cost or the
   version dependence matters. Recorded in an ADR when it lands.
4. A whole-string match entry point (I-Regexp is meant to be applied to a complete string) beside the usual search.

## Gate

The recogniser and AemiRegex agree on a stated number of generated strings, the RFC's examples pass, and every rule has a test that fails
when the rule is broken. AemiJSON's `IRegexp` is a second implementation to compare against; it is read, not trusted.
