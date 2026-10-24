# Roadmap

Every phase starts red: its tests are written, run, and seen to fail for the right reason before any code. A gate is a number or a
test that can fail. Phase 1 is done; the rest is ordered by dependency.

## Goals and how each is measured

| Goal | Measure | Status |
|---|---|---|
| Safe | Linear time for every pattern; hard limits on pattern size, nesting, program size, repetition, captures, thread-table memory | **Done** for the RE2 subset (tests: pathological, limits) |
| Fast: beat NSRegularExpression and Swift Regex | `Benchmarks/AemiRegexBench`, six workloads, median and spread, equal match counts | **Not met.** See below |
| Memory efficient | Allocation count per search; bytes per instruction; thread-table bound | 12 B per instruction and a 64 MB scratch bound; per-search allocation **not yet removed** |
| Compliant | Differential oracle per norm, in CI | RE2 syntax subset only |

### Benchmark, Phase 1 (release, Apple M2 Pro, load 10 to 13, 430 files, 1.07 MB)

| Workload | AemiRegex | NSRegularExpression | Swift Regex | Matches (all agree) |
|---|---|---|---|---|
| literal `Sendable` | 29.6 ms | 3.4 | 26.4 | 373 |
| `import\|struct\|enum\|class\|protocol` | 100.8 | 32.3 | 285.8 | 1212 |
| `func\s+\w+\(.*async` | 36.1 | 5.4 | 27.9 | 114 |
| `(\w+)\s*:\s*(\w+)\s*\{` (captures) | 131.5 | 298.7 | 700.6 | 297 |
| `(?i)todo\|fixme\|hack` | 67.0 | 21.6 | not run | 0 |
| `Q[0-9]+Z` (rare byte) | 34.9 | 4.0 | 29.0 | 0 |
| `(a+)+b`, 100,000 bytes | 12 ms | 2,858 ms **at 26 bytes** | not run | |

Reading: correct and linear, but a bare Pike VM loses to ICU by 3 to 9x wherever ICU can skip ahead. It already wins on captures and on
pathological input. **The "beat ICU" gate is Phase 3's exit.** One run per cell set on a loaded machine; rerun quiet before quoting.

## Phase 1: RE2-subset core (done)

Parser and compiler in one pass, Pike VM, limits, 103 Go-golden patterns × 23 haystacks, 10,000 generated cases against ICU,
pathological corpus. Mutation-checked: flipping greedy/lazy and dropping capture restore both turn the suite red.

## Phase 2: Unicode and the String API

Red first: Go-golden cases for `\p{L}`, `\p{Greek}`, `\P{…}`, `(?i)` with U+212A and U+017F, `[\p{Lu}&&…]` excluded.
- `\p{Category}` and `\p{Script}`, generated into compact range tables at build time (decision: generate here, or depend on
  `AemiUnicode`; the tables are the cost, a dependency is the price).
- Unicode simple case folding.
- `Range<String.Index>` results and a `String` entry point that matches in place without copying.
- A second oracle: the Rust `regex` crate (sources are in the local cargo registry), for syntax Go lacks.

## Phase 3: speed (gate: every benchmark workload at or under ICU, or the reason written down)

Each step is kept only if the benchmark shows it, and each is probed first.
1. **Borrowed input and no per-call allocation:** `Span`/`RawSpan` core; scratch pooled behind a `Mutex`. The `Span` floor
   (macOS 15) must be checked against `Array.span` availability first.
2. **Literal analysis:** required prefix, inner literal, first-byte set; scan with the Swift SIMD kernel from
   `docs/research/neon-assembly-2026-10.md` (bit-weight extraction). Start the VM only at candidates.
3. **Lazy DFA with a bounded state cache** for match/no-match and match bounds; the Pike VM then runs only on the matched span for
   captures. A reverse DFA finds the start. Cache size is a limit.
4. **One-pass and bounded backtracker** for small haystacks if the benchmark wants them.
5. Copy-on-write capture storage (see `docs/DESIGN.md`, memory bound).

Assembly stays off the list unless the revisit bar in the research note is met.

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
