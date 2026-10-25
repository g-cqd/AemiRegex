---
status: done
blocked-by: []
date: 2026-10-25
---

# 0011 — A `String` and `Substring` API, and `Span` when the floor allows

## Done

- `firstMatch`, `matches`, `forEachMatch`, `matchCount` and `isMatch` accept any `StringProtocol` (`String` and `Substring`) on both `Pattern`
  and `BacktrackingPattern`.
- A native string or substring's UTF-8 is searched in place (`withContiguousStorageIfAvailable`); non-contiguous storage falls back to a single copy.
- `Match.range(in:)` and `range(ofGroup:in:)` return `Range<S.Index>` for any `StringProtocol`.
- `Match.checkedRange(in:)` and `checkedRange(ofGroup:in:)` validate bounds against `text.utf8` and return `nil` if the string is mismatched or
  too short, rather than trapping.
- Bounded memory read: the Pike VM reads through `@safe ByteBuffer`, trapping in release if indexed out of bounds.

## Span / RawSpan status

`Array.span` requires macOS 26, while the package deployment floor is macOS 15. The internal engine interface already reads borrowed slices
through pointers and `ByteBuffer`, so adopting system `Span` when the floor advances will require updating only the wrapper.
