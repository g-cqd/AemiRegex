---
status: accepted
date: 2026-10-24
---

# 0001 — The default engine never backtracks

## Context

`NSRegularExpression` is a backtracking engine. On `^(a+)+$` it takes 11.9 ms at 18 characters, 215 ms at 22, 1.0 s at 24 and 3.8 s at 26
(`ask` research note, observed), so a pattern from an untrusted schema or a long input can hold a thread for as long as the attacker likes.
A budget turns that into an error but does not make matching linear. AemiJSON's `SchemaPattern` exists precisely to avoid this.

## Decision

The default engine is a Pike VM with a lazy DFA in front of it. Time is O(pattern x input) for every pattern and input. Constructs that
cannot run that way (backreferences, lookaround, atomic groups, possessive quantifiers) are rejected with `PatternError.unsupported`.

## Evidence

- `(a|aa)+$` on 100,000 bytes takes 0.19 ms here and 48.5 ms for ICU on **26** bytes (diary 2026-10-24-01).
- Pathological cases are a permanent test with a ceiling (`PathologicalTests`) in release and debug.

## Consequences

Full PCRE2 and ECMAScript compliance cannot come from this engine; ADR-0006 adds an opt-in one beside it. The linear-time property is
tested, not assumed: every new engine path has a pathological case.
