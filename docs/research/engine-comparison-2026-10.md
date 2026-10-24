# AemiRegex against Go, Rust, PCRE2 and ICU (2026-10-24)

**Question.** After the ICU gate was met, how does AemiRegex compare with the fastest engines available here: Rust's `regex` crate
(the engine behind ripgrep), PCRE2 with its JIT, and Go's `regexp`?

**Method (observed).** `Scripts/bench-compare.sh` freezes a copy of the corpus (431 Swift files, 1,070,930 bytes), builds one harness per
engine, and prints median milliseconds over 9 rounds (3 for Swift Regex) of counting matches. Every harness reads the same
`Benchmarks/Comparison/workloads.tsv`. Apple M2 Pro, arm64, load average 4 to 7 (other agents running). Versions: Go 1.27.3,
Rust `regex` 1.12.3 (`--release`, LTO), PCRE2 10.49 with JIT, ICU through Foundation, Swift 6.4. Two modes:
- **per file:** one haystack per file, as a search tool calls it. Per-call overhead is included.
- **one buffer:** the same bytes as a single 1 MB haystack. Per-call overhead is gone, so this is scan speed.

**Not run, so nothing is claimed:** RE2 itself, Hyperscan or Vectorscan (not installed here), and any host other than this one.

**Match counts.** The `matches` column lists every distinct count. A single number means all engines agree. They disagree on the
rows that can match empty, because engines differ on an empty match that touches the previous match, and on `\w` (Unicode in ICU,
Swift Regex and Rust's str mode; ASCII elsewhere). Speed on those rows is comparable; the counts are not.

## Summary

| | per file | one buffer |
|---|---|---|
| Rows where AemiRegex is the fastest engine | 0 of 14 | 0 of 14 |
| AemiRegex time / Rust regex (median, range) | 3.8x (1.3 to 447x) | 2.5x (1.2 to 22x) |
| AemiRegex time / PCRE2 JIT (median, range) | 3.2x (1.1 to 8.9x) | 2.3x (1.1 to 8.2x) |
| AemiRegex faster than Go regexp | 12 of 14 rows (median 3x faster) | 13 of 14 |
| AemiRegex faster than NSRegularExpression | 14 of 14 (median 8x) | 14 of 14 (median 14x) |
| AemiRegex faster than Swift Regex | 14 of 14 (median 50x) | 14 of 14 (median 50x) |

**AemiRegex is third.** It is faster than Go, ICU and Swift Regex, and slower than Rust `regex` and PCRE2-JIT on every workload.
It is not the fastest, and "fastest" is not claimed anywhere in this repository.

## Per file

| workload | Go regexp | Rust regex (ASCII bytes) | Rust regex (Unicode str) | PCRE2 JIT | AemiRegex | NSRegularExpression (ICU) | Swift Regex | matches |
|---|---|---|---|---|---|---|---|---|
| literal | 0.20 | **0.05** | **0.05** | 0.06 | 0.26 | 3.14 | 22.67 | 373 |
| alternation | 51.34 | **0.16** | **0.16** | 1.50 | 3.79 | 27.96 | 244.93 | 1216 |
| func-async | 1.00 | 0.17 | 0.17 | **0.11** | 0.47 | 4.04 | 23.36 | 114 |
| captures | 38.96 | **0.53** | 0.56 | 2.47 | 5.69 | 248.23 | 571.48 | 297 |
| case-insensitive | 40.76 | **0.14** | **0.14** | 1.69 | 1.91 | 15.02 | 242.31 | 0 |
| no-match-rare-byte | 0.04 | **0.02** | **0.02** | 0.03 | 0.18 | 3.07 | 20.80 | 0 |
| word-boundary | 16.12 | **0.05** | **0.05** | **0.05** | 0.19 | 3.72 | 102.83 | 21 |
| line-anchor | 10.85 | 0.07 | 0.07 | **0.06** | 0.19 | 3.75 | 33.89 | 0 |
| prefix-nullable | 23.95 | **1.69** | 1.70 | 2.83 | 4.19 | 126.46 | 209.99 | 753 |
| blank-lines | 14.56 | 1.80 | 1.81 | **0.53** | 4.70 | 7.23 | 43.78 | 1775, 2206 |
| optional-word | 52.53 | 12.81 | 14.68 | **6.68** | 16.87 | 24.46 | 111.37 | 384987, 384988, 385162, 510332, 510507 |
| trailing-space | 25.57 | **0.01** | **0.01** | 3.47 | 4.47 | 61.36 | 82.29 | 431, 862 |
| empty-word-edges | 44.03 | 9.89 | 11.53 | **5.50** | 14.93 | 37.45 | 155.16 | 250690, 366448 |
| empty-line-ends | 14.31 | 1.68 | 1.84 | **1.28** | 5.30 | 21.06 | 34.59 | 22423 |

## One 1 MB buffer

| workload | Go regexp | Rust regex (ASCII bytes) | Rust regex (Unicode str) | PCRE2 JIT | AemiRegex | NSRegularExpression (ICU) | Swift Regex | matches |
|---|---|---|---|---|---|---|---|---|
| literal | 0.21 | **0.04** | **0.04** | 0.05 | 0.12 | 3.69 | 22.15 | 373 |
| alternation | 62.96 | 0.16 | **0.15** | 1.53 | 3.53 | 28.72 | 242.44 | 1216 |
| func-async | 2.02 | 0.15 | 0.15 | **0.10** | 0.35 | 4.72 | 23.05 | 114 |
| captures | 48.36 | **0.65** | 0.66 | 2.60 | 5.44 | 263.14 | 573.10 | 297 |
| case-insensitive | 50.09 | **0.13** | 0.14 | 1.72 | 1.82 | 15.55 | 241.46 | 0 |
| no-match-rare-byte | 0.02 | **0.01** | **0.01** | 0.02 | 0.04 | 3.42 | 20.61 | 0 |
| word-boundary | 15.95 | **0.04** | **0.04** | **0.04** | 0.07 | 4.27 | 106.11 | 21 |
| line-anchor | 9.98 | 0.06 | 0.06 | **0.05** | 0.07 | 4.30 | 33.53 | 0 |
| prefix-nullable | 29.48 | **1.69** | 1.71 | 2.56 | 4.16 | 134.17 | 209.38 | 753 |
| blank-lines | 13.71 | 1.76 | 1.78 | **0.54** | 4.44 | 8.29 | 43.15 | 1775, 1776 |
| optional-word | 62.77 | 12.70 | 14.67 | **6.60** | 16.66 | 24.80 | 127.67 | 384557, 384558, 384732, 509902, 510077 |
| trailing-space | 27.66 | **0.00** | **0.00** | 3.31 | 4.11 | 80.24 | 82.21 | 1, 2 |
| empty-word-edges | 41.52 | 9.73 | 11.74 | **5.48** | 14.38 | 39.86 | 163.18 | 250690, 366018 |
| empty-line-ends | 12.57 | 1.62 | 1.73 | **1.28** | 4.95 | 21.11 | 32.68 | 21993 |

## Where the gap comes from

Each cause below is tied to a row; the first two are measured by comparing the two tables, the rest are read from how the other engines
work (Rust's `regex` and PCRE2 documentation and design), **not probed here**, and are hypotheses until a change shows the effect.

1. **Scan speed, not call overhead (measured).** Moving from per-file to one buffer removes the per-call cost and the ratio to Rust
   falls from 3.8x to 2.5x at the median. Most of the gap remains, so it is the scan.
2. **Alternations of literals and case-insensitive literals: 14 to 22x behind Rust (measured; cause hypothesised).** `import|struct|…`
   and `(?i)todo|fixme|hack` are sets of literals. Rust searches them with a multi-literal SIMD matcher (Teddy) and only then
   verifies. AemiRegex's prefilter scans for the first byte of any alternative, which is common in source text, so the DFA runs on most
   bytes at about 3.5 ns per byte.
3. **DFA inner loop (measured throughput: 3 to 4 ns per byte; cause hypothesised).** Rows with no literal to skip to
   (`(?m)^\s*$`, `\w*`, `\b`, `(?m)$`) run the DFA on every byte, at 3 to 4x Rust and PCRE2. The loop uses bounds-checked arrays, a flag
   load and a start-state test per byte.
4. **End-anchored patterns (hypothesis).** `[ \t]*$` takes Rust 0.00 to 0.01 ms for the whole corpus, which is not a scan of 1 MB.
   It most likely searches backwards from the end of the text. AemiRegex scans forward through every byte (4.1 ms).
5. **Per-call overhead (measured at about 0.15 ms per 431 calls on the literal row).** AemiRegex takes a lock to borrow its scratch,
   allocates the result array, and returns `[Match]`; Rust's `find_iter().count()` allocates nothing.
6. **Go beats AemiRegex on the two rows where a single literal or a rare byte decides everything** (`no-match-rare-byte`: Go 0.04 ms
   against 0.17; `literal` per file: Go 0.23 against 0.27). Go calls its optimised substring search directly.

## Work queue, in order of measured gap per effort

1. Multi-literal prefilter (Teddy-style, `tbl` nibble lookup), then verify with the DFA. Probe first: the NEON note's revisit bar
   is exactly this kernel.
2. DFA inner loop: premultiplied state ids, unchecked table reads inside one documented unsafe boundary, a tagged id so one
   compare handles match, start and dead.
3. Reverse-from-the-end search for patterns anchored at the end of the text, and inner-literal prefilters (`\w*Error`).
4. A non-allocating iteration API (`forEachMatch`, `matchCount`) and a lock-free fast path for the scratch.
5. Rerun this comparison after each step; keep a step only if its row moves.
