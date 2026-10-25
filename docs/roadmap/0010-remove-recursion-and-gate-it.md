---
status: not-started
blocked-by: []
date: 2026-10-25
---

# 0010 — Remove the recursion that remains, and gate it

ADR-0003. The engine is iterative. The depth-bounded random-pattern generators in `DifferentialTests` and
`Scripts/golden/generated/gen.go` are not. Rebuild both level by level from pools of the previous level, regenerate the fixture
(it must differ only if the grammar changed), and add a test that fails when any function in `Sources`, `Tests`, `Scripts` or `Benchmarks`
reaches itself, by a call-graph scan, broken on purpose once to prove it fires.

## Gate

The scan finds none; the generators produce the same agreement results; the ICU and Go suites stay green.
