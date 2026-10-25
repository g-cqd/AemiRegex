---
status: not-started
blocked-by: ["0007", "0008"]
date: 2026-10-25
---

# 0009 — The budgeted backtracking engine

The second engine of ADR-0006, for backreferences, lookahead, lookbehind, atomic groups, possessive quantifiers, recursion and
conditionals. Selected explicitly by the caller; the default engine never uses it.

## Contract (from ADR-0003 and ADR-0006)

An explicit stack, not recursion; a **step budget** and a **depth limit** with a typed `.budgetExceeded`; memory bounded by the same
limits as the default engine; never a hang and never a call-stack overflow, tested with the patterns that make a backtracker explode.

## Gate

Agreement with `node` and `pcre2test` on the constructs only it can run, and a pathological corpus that ends in `.budgetExceeded` within
the budget's time.
