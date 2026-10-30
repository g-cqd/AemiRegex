---
status: done
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

## Done

- `Pattern.wholeMatch` runs a whole-string twin (`WholeStringTwin`), compiled on first use and published once (an atomic state with
  acquire/release and a lock for the compile). `AtomicLazyReference` was tried first: its `load()` is not specialized into the module and
  looked up generic metadata on every call (about 450 ns a whole match). Over a limit, the twin falls back to the old check.
- `BacktrackingPattern.wholeMatch` runs the machine once from 0 with `requiredEnd`; `prefixMatch` runs anchored at 0 instead of searching every
  start.
- `WholeMatchTests` (7 tests) red at `938feaf`, green here; the suite: 177 tests pass.
- Probe, release, A/B of `938feaf` and this commit built side by side, three interleaved runs on a loaded machine (load average ~20), ns per
  name: `wholeMatch(in:)` 221 / 222 / 240 before, 194 / 185 / 187 after; anchored `isMatch` unchanged within noise. The backtracker's
  failing whole match of `a+b` on 2,000 `a`s stays under a 50,000-step budget, where it used to exhaust it.
