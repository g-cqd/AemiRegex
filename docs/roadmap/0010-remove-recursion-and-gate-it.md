---
status: done
blocked-by: []
date: 2026-10-25
---

# 0010 — Remove the recursion that remains, and gate it

ADR-0003. The engine is iterative. The depth-bounded random-pattern generators in `DifferentialTests` and
`Scripts/golden/generated/gen.go` are not. Rebuild both level by level from pools of the previous level, regenerate the fixture
(it must differ only if the grammar changed), and add a test that fails when any function in `Sources`, `Tests`, `Scripts` or `Benchmarks`
reaches itself, by a call-graph scan, broken on purpose once to prove it fires.

## Done

Both generators build level by level from pools (`DifferentialTests.PatternPools`, `Scripts/golden/generated/gen.go`), and `NoRecursionTests`
scans `Sources`, `Tests`, `Benchmarks` and `Scripts` (Swift and Go) for a function that reaches itself. The scanner is broken on purpose in
seven ways (self-call, mutual calls, a call through `self`, plus four things that must not fire) and the repository scan fails when a
recursion is put back in a Swift source or a Go script.

## Limits of the gate, stated

It reads source, not types. A function is its name and argument labels, so two overloads that differ only by parameter type look like one
function (it flagged `forwardOutcome(in:)`, which was renamed). A call through a receiver other than `self` or `Self` is not followed, so
recursion through another instance of the same type is not seen. Trailing-closure calls, computed properties and initialisers are not
scanned. It is a guard, not a proof; the proof for the engine is that it has no recursion by construction (explicit stacks, ADR-0003).

## Found on the way

Swapping the generator gave the engines patterns they had never seen, and one disagreed with Go: an empty-width loop through an assertion
(`(?i:\B*?\B|a)*`) in the DFA. Fixed by keeping such patterns on the Pike VM; see diary 2026-10-25-01.
