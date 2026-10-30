---
status: not-started
blocked-by: []
date: 2026-10-30
---

# 0017 — The constant cost of a call on short inputs

About 85 ns of a 154 ns whole-name match on a 20-byte identifier is not matching (research `whole-match-and-short-inputs-2026-10-30.md`).
Profile the split between the scratch pool checkout, the `withContiguousStorageIfAvailable` closure and the search setup, then remove what
can go: a one-thread fast path in the pool, a start state kept per pattern, a direct path for a native `String`.

Bar: the probe's anchored `isMatch` under 110 ns per name with the long-input workloads of ADR-0013's table no slower.
