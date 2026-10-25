---
status: in-progress
blocked-by: [0007]
date: 2026-10-25
---

# 0013 — Promote to the consumers

| Consumer | Use | Verdict |
|---|---|---|
| AemiJSON JSONPath `match()` / `search()` | I-Regexp (RFC 9535 refers to RFC 9485) | **Done** on branch `aemiregex` (`g-cqd/AemiJSON`, not yet merged), pinned by revision. |
| AemiJSON JSON Schema `pattern` / `patternProperties` | ECMA-262 flavoured: `^` and `$` are anchors, `\d` exists | **Blocked by 0007.** I-Regexp has no anchors, so moving it now would change what schemas mean. |
| `ask` | Three literal patterns over a short error message (`ProviderFailure+Overflow.swift`) and two test helpers | **Not moved.** No measurable gain, and it would add a dependency; revisit when 0011 has a `Substring` overload and a use that is hot. |

## What the JSONPath move measured

The old check (`IRegexp.rejectionReason`, then Swift `Regex`) against the RFC 9485 grammar on the 8,000 generated patterns of roadmap 0004:
it agreed on 6,198, accepted 1,219 patterns I-Regexp rejects (`\d`, `\s`, `\w`, `[a-c-e]`, `a{,2}`) and rejected 583 that I-Regexp accepts (nested
quantifiers, refused for the cost of a backtracker). All 426 AemiJSON tests, including the JSONPath compliance suite, pass in debug and release.
A test with a 100,000-character input and `(a*)*b` returns within the 5 s bound.

Open: the old `IRegexp.swift` stays for Schema until 0007; AemiJSON's JSONPath speed against the old engine was not measured.
