---
status: done
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

## Done

`Pattern(_:syntax: .iRegexp)` validates the RFC's grammar and translates to the RE2 machinery (`Syntax/IRegexp.swift`), whole-string by
default (`Pattern.Matching`), with offsets in the text as written and every semantic check (reversed range, repeat count order and limit,
category name) made before translation. 8,000 patterns agree with the recogniser written from the ABNF; 198 patterns x 32 haystacks agree
with Go on the RFC's own mapping, both whole-string and search; RFC section 5.1 Table 1 is a test; six mutations each turn the suite red.
Categories come from the standard library (ADR-0008). RE2 syntax gained `\p` and `\P` over general categories, checked against Go.

## Still open, and not claimed

- **AemiJSON's `IRegexp` has not been compared.** It is a second implementation to check against; that belongs to 0013, which needs a
  dependency on AemiJSON or a copy of its cases.
- **The RFC's mapping does not escape `^` and `$`**, which its grammar makes ordinary characters; AemiRegex follows the grammar and XSD.
  Whether an erratum exists was not checked.
- **`\p{C}` and `\p{Cn}` are tested by unit tests, not by Go**, which has no unassigned category.
