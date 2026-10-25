---
status: in-progress
blocked-by: []
date: 2026-10-25
---

# 0007 — The ECMAScript dialect

Flags `i m s u v` (and `g y d` as API), `\d \w \s` with ECMAScript's `\s`, `.` excluding `\n \r U+2028 U+2029`, `\uHHHH`, `\u{…}`,
`\cX`, `\0`, named groups, `\p{…}` with `Script=`, `General_Category=` and binary properties, class set notation under `v`, Annex B
leniency without `u`. Oracle: `node` (V8's irregexp), on a generated corpus run through `exec` with the `d` flag.

## Semantics the Pike VM does not have yet (ADR-0006, not probed against the oracle)

- Captures inside a quantified group are reset at the start of each iteration.
- An iteration of a loop that matches the empty string is rejected once the minimum is met.
- Multiline `^` and `$` treat `U+2028` and `U+2029` as line terminators: a three-byte lookbehind and lookahead, so the DFA cannot be used
  for such programs (they take the Pike VM).

Backreferences, lookahead and lookbehind need the engine of roadmap 0009.

## Gate

Agreement with `node` on a stated corpus, divergences listed with the oracle's answer, and the linear subset separated from the rest.

## State (2026-10-25)

Built on `BacktrackingPattern` (ADR-0011): flags `i m s` as options, `u` semantics always, `\d \w \s` (with `\w` under `i`), `.` excluding the four line
terminators, `\uHHHH` with surrogate pairs, `\u{…}`, `\cX`, `\0`, named groups and `\k<…>`, `\p{…}` over categories and scripts, modifiers
`(?i:…)`, captures reset on each iteration, empty iterations rejected, lookbehind read backwards. Agrees with `node` on the generated and curated
corpora. **Open:** binary properties and `Script_Extensions` (Go's tables have neither), the `v` flag, duplicate named groups (ES2025), `\b` under
`i` with `u` (the two extra word characters), and non-`u` mode (out of scope: ADR-0011). Status stays `in-progress` until those are built or refused by design.
