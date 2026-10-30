---
status: not-started
blocked-by: []
date: 2026-10-30
---

# 0016 — Public required literals

`Pattern.requiredLiterals: [[UInt8]]?`: byte strings such that every match contains at least one of them, or `nil` when no small set exists
(an empty match is possible, a class too wide, more than the limit). Built from the program the way the prefilter and `LiteralSet` read it,
at compile time, so it is free to ask for.

Consumers: swift-search H4 (a regex query against the index store enumerates every occurrence; required literals cut it to the names that
contain one), deadwood's pattern filters once they move to AemiRegex (analyzerkit P9), any trigram index.

Red: `foo(bar|baz)` → `["foobar", "foobaz"]` or a sound subset such as `["foo"]`; `.*` → `nil`; case-insensitive literals; soundness
checked differentially, no match of the golden corpus lacks every literal.
