# AemiRegex against Go, Rust, PCRE2 and ICU (2026-10-24, second run)

First run and the first findings: the git history of this file. This run follows five changes (a pair-set prefilter, a boxed scratch, a
tagged DFA inner loop, a literal matcher, and a C Teddy kernel driven in byte windows) and the safety work below.

**Method (observed).** `Scripts/bench-compare.sh` freezes a copy of the corpus (431 Swift files, 1,070,930 bytes), builds one harness per
engine, and prints median milliseconds over 9 rounds (3 for Swift Regex) of counting matches. Apple M2 Pro, arm64, load average 6 to 8
(other agents running). Go 1.27.3, Rust `regex` 1.12.3 (`--release`, LTO), PCRE2 10.49 with JIT, ICU through Foundation, Swift 6.4.
Two modes: **per file** (one haystack per file, per-call overhead included) and **one buffer** (the same bytes as one 1 MB haystack).
**Not run:** RE2, Hyperscan or Vectorscan (not installed), any other host. Match counts differ between engines on rows that can match
empty (engines disagree on an empty match that touches the previous one, and on Unicode `\w`); speed there is comparable, counts are not.

## Summary

| AemiRegex time / engine time (median; range) | per file | one buffer |
|---|---|---|
| Rust `regex` | 2.2x (1.0 to 177x) | 1.6x (0.9 to 4.0x) |
| PCRE2 JIT | 2.2x (0.3 to 3.6x) | 1.8x (0.2 to 3.3x) |
| Go `regexp` | faster on 13 of 14 rows | faster on 13 of 14 |
| NSRegularExpression (ICU) | faster on 14 of 14 | faster on 14 of 14 |

Before this round the medians were 3.8x and 2.5x (Rust) and 3.2x and 2.3x (PCRE2). **AemiRegex is still third overall**: slower than Rust
on every per-file row, and on all but two one-buffer rows. It is faster than PCRE2-JIT on five rows (alternation, captures,
case-insensitive, `\w*Error`, `[ \t]*$`). It is not the fastest engine and nothing here claims it is.

## What moved (AemiRegex, per file, ms)

| workload | before | after | Rust | change |
|---|---|---|---|---|
| alternation | 3.83 | 0.63 | 0.17 | 6.1x |
| case-insensitive | 1.96 | 0.49 | 0.15 | 4.0x |
| captures | 5.74 | 2.21 | 0.53 | 2.6x |
| `\w*Error` | 4.51 | 1.77 | 1.74 | 2.5x, at parity |
| `[ \t]*$` | 4.23 | 1.77 | 0.01 | 2.4x |
| literal | 0.25 | 0.14 | 0.05 | 1.8x |
| `\bclass\b` | 0.19 | 0.11 | 0.05 | 1.7x |
| `(?m)^\s*$` | 4.70 | 1.93 | 1.81 | 2.4x, near parity |
| `\w*`, `\b` (a match every 2 to 3 bytes) | 16.8, 14.7 | 17.6, 18.9 | 13.2, 10.1 | none; slightly worse |

## Per file

| workload | Go regexp | Rust regex (ASCII bytes) | Rust regex (Unicode str) | PCRE2 JIT | AemiRegex | NSRegularExpression (ICU) | Swift Regex | matches |
|---|---|---|---|---|---|---|---|---|
| literal | 0.21 | **0.05** | **0.05** | 0.06 | 0.14 | 3.18 | 23.37 | 373 |
| alternation | 51.00 | **0.17** | **0.17** | 1.53 | 0.63 | 28.78 | 247.86 | 1233 |
| func-async | 0.98 | 0.18 | 0.17 | **0.11** | 0.23 | 4.19 | 23.77 | 114 |
| captures | 39.70 | **0.53** | **0.53** | 2.50 | 2.21 | 255.09 | 581.03 | 298 |
| case-insensitive | 41.73 | 0.15 | **0.14** | 1.72 | 0.49 | 15.41 | 251.08 | 0 |
| no-match-rare-byte | 0.04 | **0.02** | **0.02** | 0.03 | 0.10 | 3.03 | 21.56 | 0 |
| word-boundary | 16.55 | **0.05** | **0.05** | **0.05** | 0.11 | 3.87 | 108.45 | 21 |
| line-anchor | 11.06 | 0.08 | 0.07 | **0.06** | 0.11 | 3.88 | 35.14 | 0 |
| prefix-nullable | 24.44 | 1.74 | **1.73** | 2.94 | 1.77 | 130.55 | 215.76 | 769 |
| blank-lines | 15.06 | 1.81 | 1.83 | **0.54** | 1.93 | 7.38 | 45.28 | 1807, 2244 |
| optional-word | 52.98 | 13.20 | 15.00 | **6.80** | 17.58 | 25.16 | 114.30 | 393196, 393197, 393371, 520802, 520977 |
| trailing-space | 26.28 | **0.01** | **0.01** | 3.56 | 1.77 | 119.19 | 153.68 | 437, 874 |
| empty-word-edges | 44.87 | 10.07 | 11.85 | **5.62** | 18.86 | 52.12 | 188.85 | 255212, 373278 |
| empty-line-ends | 14.77 | 1.92 | 1.97 | **1.31** | 3.03 | 26.58 | 46.77 | 22860 |

## One 1 MB buffer

| workload | Go regexp | Rust regex (ASCII bytes) | Rust regex (Unicode str) | PCRE2 JIT | AemiRegex | NSRegularExpression (ICU) | Swift Regex | matches |
|---|---|---|---|---|---|---|---|---|
| literal | 0.21 | **0.04** | **0.04** | 0.06 | 0.09 | 3.74 | 23.65 | 373 |
| alternation | 81.07 | **0.16** | **0.16** | 1.58 | 0.63 | 30.13 | 452.16 | 1233 |
| func-async | 2.92 | 0.16 | 0.15 | **0.11** | 0.20 | 5.02 | 24.31 | 114 |
| captures | 52.73 | **0.68** | 0.69 | 2.70 | 2.22 | 280.26 | 594.04 | 298 |
| case-insensitive | 58.33 | **0.14** | **0.14** | 1.74 | 0.39 | 16.22 | 250.57 | 0 |
| no-match-rare-byte | 0.04 | **0.01** | **0.01** | 0.02 | 0.04 | 3.55 | 21.27 | 0 |
| word-boundary | 17.34 | **0.04** | **0.04** | **0.04** | 0.07 | 4.38 | 109.94 | 21 |
| line-anchor | 10.84 | 0.06 | 0.06 | **0.05** | 0.08 | 4.49 | 34.71 | 0 |
| prefix-nullable | 32.70 | 1.81 | 1.77 | 2.64 | **1.71** | 139.44 | 216.57 | 769 |
| blank-lines | 14.99 | 1.84 | 2.00 | **0.56** | 1.83 | 9.03 | 44.71 | 1807, 1808 |
| optional-word | 78.24 | 13.86 | 16.20 | **7.26** | 17.54 | 25.87 | 122.45 | 392760, 392761, 392935, 520366, 520541 |
| trailing-space | 29.96 | **0.00** | **0.00** | 3.36 | 1.67 | 83.21 | 85.71 | 1, 2 |
| empty-word-edges | 49.74 | 10.21 | 12.50 | **6.01** | 13.31 | 41.26 | 167.09 | 255212, 372842 |
| empty-line-ends | 14.28 | 1.72 | 1.82 | **1.33** | 2.82 | 21.92 | 33.63 | 22424 |

## What each step was, and what the profiles said

Each change was kept only after a profile (`sample`) located the cost and the benchmark showed the row move.

1. **Pair-set prefilter.** Alternation 3.83 to 1.04 ms. The first bytes of five keywords are common; their first two are not.
2. **Scratch in a class.** The pool copied a struct of about thirty arrays out and back on every search: a third of the literal row was
   retain and release. A boxed scratch moved the per-call rows by 1.5 to 2x.
3. **Tagged, premultiplied DFA entries and one unchecked loop.** DFA throughput went from about 4 ns per byte to about 1.6. Dense-match
   rows needed a one-step checked fast path first, or the loop's setup dominated.
4. **Literal matcher.** A pattern that is only fixed strings is answered by verifying them at candidates: no DFA, no reverse scan.
   **The first version was never called**: the edit missed after the formatter rewrapped a signature, and the tests passed because the
   DFA returns the same answers. A per-engine counter (`SearchCounts`) now lets a test assert which engine answered.
5. **C Teddy kernel.** See the probe correction below. Driven one candidate at a time it gained little; driven in byte windows with the
   candidates of a window in one call it did. Two mistakes on the way: a batch of 256 candidates rescanned about 14 KB per search
   (alternation became 2x slower, found by profiling), and the first-byte dispatch of the verifier was still missing.

## Probe correction

The first Teddy-versus-Swift probe measured 1.4 to 1.8x and recommended no C code. **That probe was unfair**: neither loop was unrolled,
so each iteration paid its horizontal-reduce latency. With 64-byte unrolling on both, at 100 MB on arm64:

| literal set | Swift pair-set | C NEON Teddy | ratio |
|---|---|---|---|
| 5 pairs | 5.0 GB/s | 16.9 GB/s | 3.3x |
| 12 pairs | 2.7 GB/s | 16.5 GB/s | 6.1x |

That meets the revisit bar in `neon-assembly-2026-10.md` (more than 2x at 100 MB). The kernel is C intrinsics, not assembly. x86_64 timing
is **not measured** (Rosetta runs the SSSE3 path for correctness only), so the bar is met on arm64 only.

## Safety

Speed was bought with an unchecked loop and a C kernel, so each has its own net:

| Risk | Net | Evidence |
|---|---|---|
| C reads or writes past a buffer | every vector load guarded by a length test; output bounded by a caller capacity; the Swift wrapper checks every C result and **stops the program** if it is out of range | poisoned-tail and guard-band tests; four C mutations crash or fail |
| One-byte overread in an unchecked DFA loop | `unsafe` confined to two functions with the invariants written above them; debug assertions inside; poison tests for forward and reverse | forward overread caught by a poison test; the reverse one is invisible in output and caught by debug builds and ASan |
| Output buffer overrun when candidates are dense | a test where every position is a candidate, in Swift and in the C check | mutation M16 was **not caught** until this test existed |
| SIMD disagrees with the scalar reference | SIMD result compared with scalar for random tables, every offset, every size around the vector widths | Swift tests and `Scripts/teddy-check.sh` (about 105,000 checks) |
| Invalid UTF-8 and arbitrary bytes | 103 patterns and 11 literal and Unicode patterns against 60 haystacks of random and hostile bytes, DFA pipeline against the Pike VM | `MalformedInputTests` |
| x86 path never run | the C check built for x86_64 and run under Rosetta, which reports SSSE3 | `Scripts/teddy-check.sh` |
| Data races on the shared scratch | scratch boxes are in the pool or in one search, never both; 64 tasks on one pattern | TSan clean, concurrency test |

Also run clean on the final code: ASan with UBSan (zero reports), TSan (zero reports), and the debug build with its assertions.
**One mistake worth recording:** a `git checkout` of one file during mutation testing discarded my uncommitted edits to it. The file was
rebuilt from the diff of what it had been and a checkpoint commit followed; mutation runs now restore from copies.

## Work queue, in order of measured gap per effort

1. **End-anchored patterns** (`[ \t]*$`: Rust 0.01 ms against 1.77 here, 177x): search backwards from the end instead of scanning forward.
2. **An inner literal for captures** (`(\w+)\s*:\s*(\w+)\s*\{`: 4x behind Rust): search for a required literal, then run the reverse DFA from it.
3. **Per-match cost on dense empty matches** (`\w*`, `\b`): about 60 ns per match against about 35 for Rust; a forward-only path when the
   start is known (nullable patterns without assertions start at the search offset).
4. **Per-call overhead on tiny haystacks** (literal 0.14 against 0.05): a non-allocating iteration API and a lock-free scratch fast path.
5. **Verification still costs about 40% of the literal rows**; Teddy with three bytes, or a rare-byte filter, would cut candidates.
6. Rerun after each step; keep a step only if its row moves.
