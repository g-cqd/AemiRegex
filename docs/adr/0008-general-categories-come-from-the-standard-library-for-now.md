---
status: superseded
superseded-by: ADR-0009
date: 2026-10-25
---

# 0008 — General categories come from the standard library, for now

## Context

I-Regexp needs `\p{…}` over the Unicode general categories, and the RFC says an implementation MUST support them. `AemiUnicode` holds
tokenizer sets, NFD and lowercase only, not categories (read; roadmap 0005). Go's `unicode` tables would add a generator and a fixture.
The Swift standard library already exposes `Unicode.Scalar.Properties.generalCategory`.

## Decision

`UnicodeCategories` scans all 1,114,112 scalar values once, on first use, into per-category range lists, and builds each requested set
from them. A static initialiser makes the build thread-safe and happen once. There is no generated table in the repository.
Two readings of category `C`: RE2 and Go take `Cc Cf Cs Co` and have no `Cn`; XSD (so I-Regexp) takes `Cc Cf Co Cn`. The parser
carries a flag for which.

## Evidence (release, Apple M2 Pro)

- First use: **46.6 ms**. Warm: 0.56 ms per pattern. `\p{L}` compiles to 4,508 instructions; `\P{L}` and a four-category union cost the
  same warm. Scanning 140,000 bytes with `\p{L}+` takes 2.2 ms for 20,000 matches.
- Agreement with Go's categories on the golden corpus (Aé日٣€ǅ and combining marks); Go disagrees on `C` and has no `Cn`, so those are
  covered by unit tests on U+0378, which has been unassigned since Unicode 1.1.

## Consequences

The platform's Unicode version decides category membership, so a pattern's meaning can differ across OS releases for code points
assigned in between. That is acceptable for an interim source and not for a final one; roadmap 0005 decides between this, generated
tables, and an `AemiUnicode` extension, now with these numbers. A 46.6 ms first use is paid by the first `\p`, not at launch.
Class expansion is not merged into a trie, so a large class costs thousands of instructions; that is a speed item, not a correctness one.
