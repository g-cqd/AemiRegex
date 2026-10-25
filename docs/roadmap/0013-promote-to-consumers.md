---
status: done
blocked-by: []
date: 2026-10-25
---

# 0013 — Promote to the consumers

| Consumer | Use | Verdict |
|---|---|---|
| AemiJSON JSONPath `match()` / `search()` | RFC 9485 I-Regexp with anchors (`iRegexpWithAnchors`) | **Done and merged to main in `g-cqd/AemiJSON`.** CTS pass rate: 100% (466/466 valid queries, 249/249 invalid rejected). |
| AemiJSON JSON Schema `pattern` / `patternProperties` | ECMA-262 (with `u` flag) on `BacktrackingPattern` | **Done and merged to main in `g-cqd/AemiJSON`.** ReDoS-safe under a 1M-step budget; catastrophic instances fail closed promptly. |
| `ask` | 3 literal patterns in `ProviderFailure+Overflow.swift` | **Not moved.** Evaluated: 3 literal regexes on short refusal messages; adding a package dependency offers no measurable gain. |

All 428 tests in AemiJSON pass in debug and release under all sanitizers, and its CI is 100% green on GitHub Actions.
