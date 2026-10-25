---
status: accepted
date: 2026-10-25
---

# 0011 — The backtracker is a separate type, over code points

## Context

ADR-0006 promised a second, opt-in engine for backreferences, lookaround, atomic groups and possessive quantifiers. Two choices were open:
whether it shares `Pattern` and the byte program, and what it reads (bytes or scalars).

## Decision

- **A separate public type, `BacktrackingPattern`.** `Pattern.firstMatch` cannot fail and always runs in time proportional to the pattern times the
  input. A backtracker can run out of budget, so its search `throws(BacktrackError)`. Putting both in one type would turn the first promise into
  the second one's weaker promise. The caller chooses the weaker engine by naming the type.
- **It reads Unicode scalars, not bytes.** A class is a `ScalarSet` tested by binary search (an ASCII bitmap for speed); the default engine's UTF-8
  sequence expansion (`\p{L}` is 4,506 instructions there) is not needed, and a lookbehind reads backwards by decoding the scalar before the position.
  Bytes that are not valid UTF-8 are never matched by a class or `.`, as in the default engine.
- **Its own parser and instruction set.** The one-pass RE2 parser is tied to the DFA pipeline; the Perl family needs a tree (lookbehind
  direction, loop bodies that reset captures, conditionals). The tree is an arena and every walk uses an explicit stack (ADR-0003).
- **Budgets are per call**: `maxSteps` (instructions executed) and `maxStackEntries` (choice points and undo records). Exhausting either throws
  `BacktrackError.budgetExceeded`. The defaults make a hostile pattern fail in tens of milliseconds and bound memory at about 24 MB.
- **ECMAScript is the `u` flag.** The text is code points, so `u` semantics are the only ones a UTF-8 haystack can have; non-`u` (UTF-16 code unit)
  behaviour is out of scope and said so. PCRE2 is UTF mode without UCP: `\d \w \s` stay ASCII, as `pcre2test` with `utf` does.

## Consequences

Dialect differences are a table of rules (`BTRules`), not forks: line terminators, empty-loop handling (ES rejects an empty iteration, PCRE2
leaves the loop), capture reset per iteration (ES only), a backreference to an unset group (ES matches empty, PCRE2 fails). Each is checked by
the oracle suites against `node` and `libpcre2`, not argued from the specifications.
