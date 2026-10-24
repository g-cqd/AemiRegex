# Roadmap

Every phase starts red: its tests are written, run, and seen to fail for the right reason before any code. A gate is a number or a
test that can fail. Phase 1 is done; the rest is ordered by dependency.

## Goals and how each is measured

| Goal | Measure | Status |
|---|---|---|
| Safe | Linear time for every pattern; hard limits on pattern size, nesting, program size, repetition, captures, thread-table memory and DFA cache | **Done** for the RE2 subset |
| Fast: beat NSRegularExpression and Swift Regex | `SpeedGateTests` (release, interleaved medians, equal match counts) and `Benchmarks/AemiRegexBench` | **Met** on every measured workload. See below for the margins and what is not covered |
| Memory efficient | Allocation count per search; bytes per state; cache and table bounds | Bounded (64 MB Pike tables, 2 MB per DFA); per-search allocation removed for matching without captures; not yet minimised |
| Compliant | Differential oracle per norm, in CI | RE2 syntax subset, checked against Go on 8,000 generated and 2,369 curated cases |

### Benchmark (release, Apple M2 Pro, `ask/Sources`: 431 files, 1.07 MB; two runs at load 9 to 15, median ms)

| Workload | AemiRegex | NSRegularExpression | Swift Regex | Matches |
|---|---|---|---|---|
| literal `Sendable` | 0.3 | 3.3 to 4.1 | 24 to 34 | 373 |
| `import\|struct\|enum\|class\|protocol` | 3.9 to 6.3 | 30 to 42 | 280 to 302 | 1216 |
| `func\s+\w+\(.*async` | 0.5 | 4.5 to 4.7 | 27 to 29 | 114 |
| `(\w+)\s*:\s*(\w+)\s*\{` (captures) | 6.5 to 6.9 | 280 to 480 | 780 to 870 | 297 |
| `(?i)todo\|fixme\|hack` | 2.4 | 22 to 23 | not run | 0 |
| `Q[0-9]+Z` | 0.2 | 3.7 to 3.8 | 26 to 28 | 0 |
| `\bclass\b` | 0.2 to 0.3 | 4.5 to 4.9 | 124 to 128 | 21 |
| `(?m)^import \w+$` | 0.2 | 4.4 to 4.8 | 40 to 63 | 0 |
| `\w*Error` | 4.6 to 9.5 | 161 to 173 | 231 to 483 | 753 |
| `(?m)^\s*$` (can match empty) | 5.1 to 18 | 7.9 to 12.6 | 52 to 87 | 2206 vs 1775 (ICU) |
| `\w*` (can match empty) | 20 to 40 | 27 to 95 | 128 to 372 | 384,988 vs 510,332 |
| `[ \t]*$` | 4.6 to 6.4 | 68 to 82 | 85 | 431 vs 862 (ICU) |
| `\b` | 15.5 | 39.8 to 42 | 170 | 250,690 (Swift Regex 366,448) |
| `(?m)$` | 6.0 | 22 | 36 | 22,423 |
| `(a\|aa)+$`, 100,000 bytes | 0.19 | 48.5 **at 26 bytes** (exponential) | not run | |

Margins: 3 to 45x on most rows. **The thin rows are `(?m)^\s*$` (about 1.0 to 1.6x, and the noisiest) and `\w*` (about 1.3 to 2.4x).** Both
can match empty, run the DFA with no literal to skip to, and (for `\w*`) produce a match every 2 to 3 bytes. Match counts differ on
the nullable rows by design: ICU and Swift Regex report an empty match that touches the previous match, RE2 and Go do not, and `\w` is
Unicode in ICU and ASCII here. Speed on those rows is comparable, counts are not. The corpus is a live repository, so counts drift
between runs.

**Not covered by the gate:** a pattern whose DFA outgrows its 2 MB cache falls back to the Pike VM, which was slower than ICU on every
workload before the DFA existed (the fallback is correct and bounded, not fast); Unicode classes and `String` input do not exist yet;
single-core only; one machine, one architecture, a loaded host.

## Phase 1: RE2-subset core (done)

Parser and compiler in one pass, Pike VM, limits, 103 Go-golden patterns × 23 haystacks, 10,000 generated cases against ICU (no
assertions: ICU differs from RE2 there), 2,000 Go-generated patterns × 4 haystacks with assertions and flags, pathological corpus.
Mutation-checked: nine mutations (greedy/lazy, capture restore, four in the assertion machinery, the empty-match retry, two in the SIMD scan)
each turn the suite red; one of them (an overread by one byte in the pair scan) was invisible until a test poisoned the bytes past the end.

## Phase 2: Unicode and the String API

Red first: Go-golden cases for `\p{L}`, `\p{Greek}`, `\P{…}`, `(?i)` with U+212A and U+017F, `[\p{Lu}&&…]` excluded.
- `\p{Category}` and `\p{Script}`, generated into compact range tables at build time (decision: generate here, or depend on
  `AemiUnicode`; the tables are the cost, a dependency is the price).
- Unicode simple case folding.
- `Range<String.Index>` results and a `String` entry point that matches in place without copying.
- A second oracle: the Rust `regex` crate (sources are in the local cargo registry), for syntax Go lacks.

## Phase 3: speed (the gate is met; what is left is margin and memory)

Done, in order, each checked by the benchmark and a test that can fail:
1. **SIMD prefilter** (`Scan/ByteScan.swift`, `Scan/Prefilter.swift`): a literal prefix scanned as a byte pair, else the set of possible
   first bytes (at most 8). Swift SIMD with bit-weight lane extraction, per `docs/research/neon-assembly-2026-10.md`. No assembly.
2. **Lazy DFA** (`Engine/LazyDFA.swift`) with a byte limit on its cache, equivalence classes for bytes, pending assertions resolved by
   the next byte, and matches reported one byte late. Forward leftmost-first for the match end; a reverse DFA on the mirrored program for
   the start; the Pike VM runs on that window only for captures. Handles `^ $ \b \B`, flags, and patterns that match empty.
3. **Scratch pool** (`Engine/SearchScratch.swift`): DFA caches and Pike buffers are reused across searches and never shared between
   concurrent ones.
4. **In-place scratch access and an inline whole-match range** after measuring two per-match costs on empty-match-dense input.

Still open, in the order the data suggests:
1. **Thin rows** (`(?m)^\s*$`, `\w*`): premultiplied state ids and unchecked table reads inside one documented unsafe boundary; fewer
   transitions per byte for a state that loops on itself.
2. **Cache full:** clear the cache and continue (as RE2 does) instead of falling back to the Pike VM for the rest of the call.
3. **A multi-literal prefilter** (Teddy, `tbl`-based nibble lookup) for alternations whose first bytes number more than 8. This is the
   one place NEON-specific code might still pay; probe it first.
4. **Borrowed input:** `Span` needs macOS 26 (`Array.span` is unavailable at the macOS 15 floor; probed), so the core uses
   `UnsafeBufferPointer` inside the module and the public API takes `[UInt8]`. Add `String` and `Substring` entry points in Phase 2
   without a copy, and revisit `Span` when the floor allows.
5. **Copy-on-write capture storage** in the Pike VM (see `docs/DESIGN.md`).
6. **Native x86_64 timing.** Nothing here is measured off arm64.

## Phase 4: dialects and norms

| Norm | What it needs | Oracle and corpus |
|---|---|---|
| **RFC 9485 I-Regexp** | Strict mode (nothing outside the RFC's grammar), whole-string match, `\p{…}` | RFC examples; the JSON Schema test suite's `pattern` cases; AemiJSON's `IRegexp` (second consumer) |
| **Rust regex syntax** | `(?x)`, class set operations `[a&&b]`, `\b{start}`, `\p{…}` | Rust crate as oracle |
| **ECMAScript** (`u` and `v` flags) | `\u{…}`, `.`/`\s`/`$` differences, no backreferences or lookaround | `node` as oracle; test262 `RegExp` cases that fit |
| **PCRE2 subset** | The linear subset: no backreferences, lookaround, atomic or possessive | `pcre2test` (installed locally) and PCRE2's `testdata` |
| **POSIX ERE and BRE** | Leftmost-**longest** matching, a different rule from leftmost-first | AT&T `testregex` corpus; the system `regexec` as oracle |
| **UTS #18** | Level 1 properties and case rules | Unicode data files |

**A problem with "fully compliant" as stated.** Backreferences, lookaround, atomic groups and possessive quantifiers cannot run in
linear time, and PCRE2 and ECMAScript require them. Full compliance with those two norms and "safe" cannot both hold in one engine.
Proposal, pending the owner (Question 1): compliance is defined per dialect over the **linear subset**, written down as a table of
excluded features. A separate, opt-in backtracking engine with a step budget that throws `.budgetExceeded` can cover the rest, so
the default engine stays safe. It is not planned until the owner says yes.

## Phase 5: hardening

libFuzzer target (Linux), differential fuzzing against the oracles, ASan/TSan/UBSan in CI, a TLA+ or Lean model of the thread-order
invariant (leftmost-first) and of the DFA cache (a bound that eviction preserves). Native x86_64 timing on a real host.

## Phase 6: promotion

AemiJSON's `SchemaPattern` and JSONPath `CompiledRegex` move from Swift `Regex` to AemiRegex (I-Regexp mode). `ask` replaces its
three runtime patterns and two test helpers (roadmap 0059 there). Each consumer pins AemiRegex by revision.

## Questions for the owner

1. Is "compliant" per dialect over the linear subset acceptable, with an opt-in budgeted backtracker later for full PCRE2/ECMAScript?
2. Unicode tables: generated here (zero dependencies) or taken from `AemiUnicode`?
3. Which dialects first after RE2: I-Regexp (unblocks AemiJSON) or ECMAScript/PCRE2?
4. Repository: `g-cqd/aemiregex` is created locally only. Create it on GitHub (public or private), and move it to `Aemi-Studio`?
5. A native Intel or AMD host for the x86_64 numbers, or accept Rosetta for correctness only.
