---
status: done
blocked-by: []
date: 2026-10-24
---

# 0001 — RE2 syntax core and the Pike VM

Parser and compiler in one pass (no syntax tree, no recursion), the Pike VM, limits with typed errors, `[UInt8]` API with byte offsets.

## Done

103 Go-golden patterns x 23 haystacks, 10,000 generated cases against ICU (no assertions), 2,000 Go-generated patterns x 4 haystacks with
assertions and flags, a pathological corpus with a ceiling, the joint memory bound on instructions x capture slots. ADR-0001, ADR-0002.
