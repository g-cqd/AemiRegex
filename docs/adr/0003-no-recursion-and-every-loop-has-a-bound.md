---
status: accepted
date: 2026-10-25
---

# 0003 — No recursion, and every loop has a bound

## Context

The owner's rule: remove any recursion, so no input can overflow the call stack and nothing can loop forever. A backtracker is where
unbounded recursion usually lives, and one is planned (ADR-0006).

## Decision

No function calls itself, directly or through others, in the library, the tests or the scripts. Work that is naturally a tree (parsing
nested groups, epsilon closure, alternation, repetition) uses an explicit stack whose growth is a limit (`maxNestingDepth`, the program
size). Every loop is bounded by an input length, a limit, or a step budget; the backtracking engine of ADR-0006 gets a step budget and
a depth limit as part of its contract. Random-pattern generators build level by level from pools of the previous level.

## Evidence

A call-graph audit by function name, with every reported cycle examined by hand, found no recursion in the engine (the parser, Pike VM,
DFA, closure walk, UTF-8 sequence splitting and fragment builders are iterative). The cycles it reported were name collisions (`firstIndex` overloads, `Parser.compile` against
`ClassCompiler.compile`) plus the **depth-bounded generators** in `DifferentialTests` and `Scripts/golden/generated/gen.go`, which are
genuinely recursive. 100,000 nested parentheses are rejected by the depth limit without recursing (`ParserTests`).

## Consequences

Roadmap 0010 removes the two generators and adds a gate that fails if a function reaches itself. Until it lands the rule is met in the
library and not yet in the test generators, and that is stated here and nowhere hidden.

## Update, 2026-10-25

Roadmap 0010 landed: the two generators are iterative and `NoRecursionTests` fails if any function in the Swift or Go sources reaches itself.
The rule now holds in the library, the tests, the benchmarks and the scripts. The gate is a heuristic over labels and receivers (limits in
roadmap 0010), so it complements the by-construction argument for the engine and does not replace it.

