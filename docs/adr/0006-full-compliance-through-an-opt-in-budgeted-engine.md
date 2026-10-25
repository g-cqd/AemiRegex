---
status: accepted
date: 2026-10-25
---

# 0006 — Full dialect compliance through an opt-in, budgeted engine

## Context

The owner asked for I-Regexp, ECMAScript and PCRE2, and then for **everything**, including what needs backreferences and lookaround. Those
cannot run in linear time, so "compliant" and "never exponential" cannot both hold in one engine.

## Decision

- Each dialect is a front end over the same program and engines, with its own oracle (I-Regexp: the RFC's grammar and a Go translation;
  ECMAScript: `node`; PCRE2: `pcre2test`; RE2: Go).
- Constructs outside the linear subset are served by a **second engine**, a backtracker, selected explicitly by the caller. It is an
  explicit-stack machine (ADR-0003) with a **step budget and a depth limit**, and exhausting either is a typed error
  (`.budgetExceeded`), never a hang or a crash. The default engine and its promise are unchanged.
- A dialect's compliance is stated per engine: what the linear engine accepts, what the backtracker adds, what neither does.

## Consequences

Roadmap 0007 (ECMAScript), 0008 (PCRE2) and 0009 (the backtracker) carry the work; I-Regexp (0004) is entirely inside the linear subset.
ECMAScript needs two semantics the Pike VM lacks (captures reset on each loop iteration, and an iteration that matches empty is
rejected); both are in 0007's scope and not yet probed against the oracle.
