---
status: done
blocked-by: []
date: 2026-10-25
---

# 0009 — The budgeted backtracking engine

`BacktrackingPattern` (ADR-0011): the second engine of ADR-0006, for backreferences, lookahead, lookbehind, atomic groups and possessive
quantifiers. Selected by naming the type; the default engine never uses it.

## Contract (from ADR-0003 and ADR-0006)

An explicit stack, not recursion; a **step budget** and a **stack-entry budget** with a typed `.budgetExceeded`; never a hang and never a
call-stack overflow. Tested with `(a+)+b` over 60 characters, a 100,000-entry stack, 10,000 nested groups, and nested counted repetitions.

## Gate (met)

Agreement with `node` and `libpcre2` on generated and hand-picked cases, and a pathological corpus that ends in `.budgetExceeded`.
Measured: 12,000 generated cases per dialect plus 416 (ECMAScript) and 415 (PCRE2) curated, all agreeing, none skipped for budget.

## Not in it

Recursion and subroutine calls, conditionals, other verbs, and `\G` are PCRE2 work (0008). A literal prefilter and a start-position
optimization are not built: every start position runs the machine. Speed was not measured and is not claimed.
