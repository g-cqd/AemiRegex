---
status: not-started
blocked-by: []
date: 2026-10-25
---

# 0011 — A `String` and `Substring` API, and `Span` when the floor allows

Today only `[UInt8]` is accepted and results are byte offsets. Add entry points over a `String`'s UTF-8 without a copy, results as
`Range<String.Index>`, and a non-allocating iteration (`forEachMatch`, `matchCount`). `Array.span` needs macOS 26 and the floor is 15;
revisit `Span` when the floor moves.
