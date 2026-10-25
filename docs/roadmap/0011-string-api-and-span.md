---
status: in-progress
blocked-by: []
date: 2026-10-25
---

# 0011 — A `String` and `Substring` API, and `Span` when the floor allows

## Done

`firstMatch(in: String, from: String.Index?)`, `matches(in:)`, `forEachMatch(in:_:)`, `matchCount(in:)` and `isMatch(in:)` for `String`
and for `[UInt8]`, and `Match.range(in:)` / `range(ofGroup:in:)` mapping a match back to `String.Index`. A native string's UTF-8 is searched
in place (no copy); a bridged `NSString` is copied once (tested on Darwin). Every search takes a borrowed buffer: the Pike VM reads it
through `ByteBuffer`, a `@safe` wrapper whose only read is a checked subscript (it traps in release; four exit tests prove it), so the
bounds-checked reference engine stays bounds-checked. `matchCount` is 25 to 37% faster than `matches(in:).count` on literal rows and
11% on `\w*` (unchanged with captures); the `String` path is as fast as the bytes path within noise.

## Still open

- **`Substring`** is not accepted; `String(substring)` copies. A `Substring` shares its base's storage, so an overload is possible.
- **`Span` / `RawSpan`**: `Array.span` needs macOS 26 and the floor is 15; the internal type is already a borrowed buffer, so adopting `Span`
  later changes the wrapper, not the engines.
- **`Match.range(in:)` traps** if the string is not the one searched and the offsets fall outside it (fail-closed, documented as a
  precondition); a checked variant returning `nil` is not built.
