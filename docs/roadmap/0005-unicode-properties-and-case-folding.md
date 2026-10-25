---
status: done
blocked-by: []
date: 2026-10-25
---

# 0005 — Unicode: properties, scripts, case folding

`\p{L}`, `\pN`, `\p{Greek}`, `\P{…}` for RE2 syntax, Unicode simple case folding for `(?i)` (so `(?i)k` matches U+212A, as RE2 and Go
do), and a decision on the table source. `AemiUnicode` holds only tokenizer sets, NFD and lowercase, not categories, scripts or fold
orbits; the options are extending it in the Aemi repository (a shared package: its own worktree, review and pin) or generating tables from
Go's `unicode` package here. Decide with the sizes and the version dependence measured. ADR-0008 holds the interim source (the standard library, general categories only,
46.6 ms on first use) and its numbers; scripts, binary properties and case folding are not covered by it.

## Done

Scripts, 42 category aliases, loose property names, `Any`, `Assigned`, `Ascii`, `Lc`, `Cn`, and Unicode simple case folding for RE2 syntax,
all from one generated table set (ADR-0009, which supersedes ADR-0008). Checked against Go on 142 patterns x 40 haystacks, against the
standard library for every character assigned before Unicode 15, and by six mutations. Cold `\p{L}` went from 46.6 ms to 0.85 ms.

## Still open, and not claimed

- **Binary properties and `Script_Extensions`** (ECMAScript `\p{Alphabetic}`, `\p{scx=…}`): roadmap 0007. Go has neither.
- **Case folding for ECMAScript and PCRE2**, which differ from RE2's; they bring their own tables.
- **`\w`, `\d`, `\s`, `\b` stay ASCII**, as in RE2 and Go. A Unicode `\b` is not built.
- **A large class still costs thousands of instructions** (`\p{L}` is 4,506); merging UTF-8 sequences into a trie is a speed item (0006).
- **Promoting the tables to `AemiUnicode`** is a change to a shared package, unmade.
