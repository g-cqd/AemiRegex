# AemiRegex design

A regular-expression engine whose search time is O(pattern × input) for every pattern. Safety is a property of the algorithm, not a
budget: there is no backtracking, so no pattern can make a search exponential. The cost of a pattern is bounded at compile time by
``Pattern/Limits``.

## Layout

| Stage | Files | Notes |
|---|---|---|
| Parse and compile in one pass | `Syntax/Parser*.swift`, `Syntax/Frame.swift` | No syntax tree. Groups live on an explicit stack (no recursion), so nesting depth is a limit, not a stack overflow. |
| Program | `Program/*.swift` | A flat `ContiguousArray<Instruction>` of 12 bytes each. Jumps are relative, so `x{n,m}` copies a fragment without relocation. |
| Classes | `Program/ClassCompiler.swift`, `Utf8Sequences.swift` | A scalar set becomes byte ranges over UTF-8 (the RE2 and Rust `utf8-ranges` algorithm); ASCII becomes a 256-bit set. |
| Prefilter | `Scan/*.swift` | A literal prefix or the set of possible first bytes, scanned with Swift SIMD. It may offer a position where no match starts, never skip one where a match does. |
| Lazy DFA | `Engine/LazyDFA.swift`, `ByteClasses.swift`, `EpsilonWalker.swift`, `NeighborContext.swift` | Forward unanchored leftmost-first for the match end; reverse anchored longest (on the mirrored program) for the start. States are built on first use under a byte limit. |
| Pike VM | `Engine/PikeVM.swift` | Thread list in priority order gives leftmost-first matches with captures. Runs on the matched window for captures, and as the fallback when the DFA cache fills. It is the reference the DFA is tested against (`Engine.pikeOnly`). |
| Scratch pool | `Engine/SearchScratch.swift` | DFA caches and Pike buffers, one set per concurrent search, taken under a short lock. |
| API | `Pattern.swift`, `Match.swift`, `PatternError.swift` | Byte offsets into UTF-8. `Pattern` is a `Sendable` value. |

## Semantics decided

- **Syntax: RE2's**, minus what is not built yet (see the roadmap). Backreferences, lookaround, atomic groups and possessive quantifiers
  are rejected with `.unsupported`. They cannot run in linear time.
- **Match rule: leftmost-first** (Perl, RE2, Go), not leftmost-longest. A POSIX mode needs a different rule and is a roadmap item.
- **Text: UTF-8 bytes.** `.`, classes and negated classes match whole scalars only. Bytes that are not valid UTF-8 never match them.
  A match never starts inside a valid multi-byte scalar.
- **`\d \w \s \b` are ASCII**, as in RE2 and Go. `(?i)` folds ASCII letters only (see gaps).
- **Iteration** (`matches(in:)`): an empty match that abuts the previous match is skipped, and the position advances one scalar.
  Probed against Go: `a*` on `baaac` gives `[0,0] [1,4] [5,5]`.

## How a search runs

1. The prefilter jumps to the next position a match could start, while the forward DFA is in its start state.
2. The forward DFA reads bytes to the end of the leftmost-first match. State = the ordered thread list of the Pike VM, plus: a match was
   seen (stops new threads), a match ended just before the last byte, and the kind of the last byte. Assertions stay pending in the list
   and resolve on the next byte, so a match is reported one byte late and the end of the text is a final step.
3. The reverse DFA scans back from that end over the mirrored program and finds the smallest start at or after the search offset. This
   is the leftmost-first start: a smaller start would contradict the forward result, a larger one would not be the smallest.
4. Without captures the match is `start ..< end`. With captures the Pike VM runs anchored at `start` and stops at `end`.
5. An empty match inside a multi-byte scalar is dropped and the search resumes one byte later (the Pike VM never starts there).
6. A DFA whose cache would exceed its limit gives up for the rest of the call and the Pike VM answers.

## Where this deliberately differs from the oracles

| Case | Go 1.27 | RE2, Rust | AemiRegex | Why |
|---|---|---|---|---|
| Duplicate group name `(?P<n>a)(?P<n>b)` | accepted | rejected | rejected | A name that maps to two groups is ambiguous. Probed: Go accepts it. |
| Group name `(?P<1a>x)` | accepted | rejected (Rust) | rejected | Names are identifiers. |
| Nullable loop body `(a*)*` | `(x+)?` form | same | `(x+)?` form | Keeps the captures the oracle gives; covered by the golden file. |

## Known gaps (each has a roadmap item; none is claimed as supported)

- Unicode: `\p{…}`, `\P{…}`, Unicode case folding. `(?i)k` does not match U+212A, which RE2 and Go do.
- A `String` and `Substring` API (`Range<String.Index>`); today only `[UInt8]`.
- A DFA that fills its cache falls back to the Pike VM, which is correct but slower than ICU.
- Input is `[UInt8]`; `Span` needs macOS 26 and the floor is 15.

## Memory bound

The Pike VM holds two thread tables of `instructions × slots` `Int` entries each, plus two sparse sets. `Limits.maxThreadTableEntries`
(default 4M entries, so 64 MB for both tables) bounds the product at compile time, so a pattern with many groups and a large program is
rejected instead of allocating gigabytes (test: `many capture groups in a large program are rejected…`). Each lazy DFA is bounded by
`Limits.maxDFACacheBytes` (default 2 MB); a pooled scratch holds two, and the pool holds at most one scratch per concurrent search.
**Open:** copy-on-write slot storage, as RE2 does, would cut the table from instructions × slots to threads × slots and let
the default bound shrink. Not measured yet.
