---
status: not-started
blocked-by: ["0004"]
date: 2026-10-25
---

# 0005 — Unicode: properties, scripts, case folding

`\p{L}`, `\pN`, `\p{Greek}`, `\P{…}` for RE2 syntax, Unicode simple case folding for `(?i)` (so `(?i)k` matches U+212A, as RE2 and Go
do), and a decision on the table source. `AemiUnicode` holds only tokenizer sets, NFD and lowercase, not categories, scripts or fold
orbits; the options are extending it in the Aemi repository (a shared package: its own worktree, review and pin) or generating tables from
Go's `unicode` package here. Decide with the sizes and the version dependence measured.

## Gate

Go-golden cases for categories, scripts and folding; a test that a fold orbit and the stdlib's case properties agree on a stated sample;
the cost of compiling a class with `\p` measured (the interim stdlib scan costs about 55 ms the first time, to be measured).
