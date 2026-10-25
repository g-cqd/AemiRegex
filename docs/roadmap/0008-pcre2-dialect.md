---
status: in-progress
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

## State (2026-10-25)

Built on `BacktrackingPattern`: `i m s x n` flags, atomic groups, possessive quantifiers, lookahead, lookbehind read forward with each branch tried
from the farthest start (as PCRE2 10.43+ does, up to 255 characters), branch reset `(?|`, `\A \z \Z \K \R \h \H \v \V \N \Q…\E`, `\g`,
`\k`, `(?P<n>)`, `(?P=n)`, `(?'n')`, POSIX classes, `{,m}`, spaces in `{ n }`, octal and `\o{}`, `\x{…}`, `\N{U+…}`, `(*FAIL)`, comments, and PCRE2's global
matching. Agrees with `libpcre2` 10.49 on the generated and curated corpora. **Open:** recursion and subroutine calls (`(?R)`, `(?1)`, `(?&n)`),
conditionals, the other verbs, `\G`, `\X`, callouts, UCP mode, the `J` flag, `xx`, binary properties. Status stays `in-progress`.
