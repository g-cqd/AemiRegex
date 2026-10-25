---
status: not-started
blocked-by: []
date: 2026-10-25
---

# 0008 — The PCRE2 dialect

`$` before a final newline, `\Z \z \A \G`, `\h \H \v \V \R \N`, `\Q…\E`, `\x{…}`, octal and `\o{}`, `\e`, `\cx`, named groups in three
syntaxes, flags `imsxnUJ`, extended mode, POSIX classes, `\b` as backspace inside a class, `(*UTF)` style leading verbs. Oracle:
`pcre2test` (10.49 here, Unicode 17).

Captures in a loop whose body matches empty may differ from the RE2 family; the oracle decides each case. Backreferences, lookaround,
atomic groups, possessive quantifiers, recursion and conditionals need roadmap 0009.

## Gate

Agreement with `pcre2test` on a stated corpus, with the linear subset and the rest separated and every divergence listed.
