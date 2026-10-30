---
status: not-started
blocked-by: []
date: 2026-10-30
---

# 0015 — `wholeMatch(in:)` is the whole-string match

`wholeMatch` is leftmost-first then a range check, so `Pattern("a|ab").wholeMatch(in: "ab")` is `nil` (research
`whole-match-and-short-inputs-2026-10-30.md`). Both types.

- **Pattern:** a whole-string twin, compiled on first use from the same source and limits, cached in a `Mutex` box that copies share; a
  pattern compiled `.wholeString` answers with itself.
- **BacktrackingPattern:** the machine runs anchored at 0 and a `match` instruction at any other position than the end fails, so the
  search backtracks into the next alternative. Subroutine returns and `\K` keep their meaning.

Red: `a|ab` on `ab`, `(a|ab)(c|bcd)(d*)` captures against Swift `Regex`, an ECMAScript and a PCRE2 alternation, a backtracker budget that a
failing whole match must not exceed by scanning, the I-Regexp syntaxes unchanged. Green: the same, and the probe's per-name time no worse.
