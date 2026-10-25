# AemiRegex against Go, Rust, PCRE2 and ICU (2026-10-25, third run)

Follows `engine-comparison-2026-10.md` (its method applies). **The corpus differs**: a frozen copy of `ask/Sources` taken for this session
(508 files, 1,277,680 bytes; the second run used 431 files), so numbers here compare only with each other. Apple M2 Pro, arm64, one host, load
not recorded. Go 1.27.3, Rust `regex` 1.12.3, PCRE2 10.49 with JIT, Swift 6.4. Not run: RE2, Hyperscan, any other host.

## What changed in this run, one step at a time (AemiRegex, per file, ms)

Each step was measured with `Scripts/bench-compare.sh` on the same frozen corpus; run-to-run spread on rows a step does not touch was up to
about 5% (the nullable rows moved +4% to +7% in the last step without running any changed code).

| workload | start | harness counts with `matchCount` | no captures when only counting | terminal-byte jump |
|---|---|---|---|---|
| literal | 0.16 | 0.14 | 0.14 | 0.14 |
| alternation | 0.77 | 0.70 | 0.68 | 0.67 |
| captures | 2.63 | 2.51 | **1.99** | **0.46** |
| trailing-space | 0.07 | 0.04 | 0.04 | 0.04 |
| optional-word | 21.15 | 19.50 | 18.90 | 19.83 |
| empty-word-edges | 16.33 | 15.21 | 14.60 | 15.68 |

1. **The harness now counts with `matchCount(in:)`** like the other engines (`matches(in:)` also built a `Match` and a captures array for
   each match). This is a change of method, not of the engine: it moved most rows 3% to 10%.
2. **`matchCount` and `isMatch` no longer run the Pike VM** to fill in capture groups nobody reads (`CountingTests`). It moved only the
   `captures` row: 2.51 to 1.99 ms.
3. **A terminal byte** (`TerminalByte`, roadmap 0006): when every match ends with one ASCII byte that nothing else in the pattern can
   consume (`{` in `(\w+)\s*:\s*(\w+)\s*\{`), the search jumps between occurrences of that byte with a SIMD scan and runs one reverse search,
   bounded below by the search start, from each. The first occurrence that ends a match ends the leftmost one, because no match can contain two
   of them. 1.99 to 0.46 ms. The reverse searches cover disjoint ranges, so the total stays linear in the haystack.

After the last step `search` was split into one function per strategy (a lint limit on complexity); a fourth run reproduced `captures` at 0.46 ms and moved no
other row by more than the spread.

## Summary (this run, rows with a measured Rust time of 0.005 ms or more are divided as measured, smaller ones by 0.005)

| AemiRegex time / engine time (median; range) | per file | one buffer |
|---|---|---|
| Rust `regex` (ASCII bytes) | 1.64x (0.75 to 4.0x) | 1.32x (down to 0 to 4.2x) |
| PCRE2 JIT | 2.00x (0.01 to 3.5x) | 1.63x (down to 0 to 3.3x) |

AemiRegex is **still third overall**: slower than Rust on 13 of 14 per-file rows, faster on one (`captures`, 0.46 against 0.61 ms, which the
terminal byte makes possible for this pattern shape and no other row). It is faster than PCRE2 JIT on five rows. Before this run the
medians on the same corpus were 1.82x (Rust) and 2.00x (PCRE2). The per-row ranges are wide and the sample is one corpus on one machine:
nothing here says AemiRegex is the fastest engine, or that `captures` generalizes beyond patterns that end in such a byte.

## Per file

| workload | Go regexp | Rust regex (ASCII bytes) | Rust regex (Unicode str) | PCRE2 JIT | AemiRegex | NSRegularExpression (ICU) | Swift Regex | matches |
|---|---|---|---|---|---|---|---|---|
| literal | 0.26 | **0.06** | **0.06** | 0.07 | 0.14 | 3.76 | 27.19 | 428 |
| alternation | 59.14 | **0.19** | **0.19** | 1.78 | 0.67 | 33.83 | 289.98 | 1430 |
| func-async | 1.15 | 0.20 | 0.19 | **0.13** | 0.28 | 4.80 | 27.81 | 140 |
| captures | 46.30 | 0.61 | 0.62 | 2.95 | **0.46** | 294.55 | 678.73 | 332 |
| case-insensitive | 48.88 | **0.17** | **0.17** | 1.98 | 0.61 | 18.25 | 289.27 | 0 |
| no-match-rare-byte | 0.05 | **0.03** | **0.03** | 0.04 | 0.10 | 3.67 | 25.24 | 0 |
| word-boundary | 19.33 | **0.06** | **0.06** | **0.06** | 0.12 | 4.49 | 122.29 | 26 |
| line-anchor | 12.99 | 0.08 | 0.09 | **0.07** | 0.13 | 4.53 | 40.60 | 0 |
| prefix-nullable | 28.63 | **2.00** | 2.02 | 3.37 | 2.23 | 150.55 | 250.80 | 856 |
| blank-lines | 17.46 | 2.09 | 2.13 | **0.64** | 2.26 | 8.84 | 52.17 | 2082, 2590 |
| optional-word | 62.85 | 15.43 | 17.65 | **7.94** | 19.83 | 29.63 | 134.39 | 463488, 463489, 463684, 613014, 613210 |
| trailing-space | 30.60 | **0.01** | 0.02 | 4.14 | 0.04 | 73.66 | 99.69 | 508, 1016 |
| empty-word-edges | 52.75 | 11.71 | 13.92 | **6.58** | 15.68 | 45.03 | 184.62 | 299052, 438635 |
| empty-line-ends | 17.25 | 2.00 | 2.10 | **1.52** | 3.29 | 24.88 | 40.19 | 26800 |

## One 1 MB buffer

| workload | Go regexp | Rust regex (ASCII bytes) | Rust regex (Unicode str) | PCRE2 JIT | AemiRegex | NSRegularExpression (ICU) | Swift Regex | matches |
|---|---|---|---|---|---|---|---|---|
| literal | 0.24 | **0.05** | **0.05** | 0.06 | 0.10 | 4.19 | 26.73 | 428 |
| alternation | 75.07 | **0.18** | **0.18** | 1.79 | 0.75 | 34.37 | 288.48 | 1430 |
| func-async | 2.41 | 0.18 | 0.17 | **0.12** | 0.24 | 5.67 | 27.39 | 140 |
| captures | 57.30 | 0.81 | 0.80 | 3.07 | **0.42** | 312.53 | 676.58 | 332 |
| case-insensitive | 59.73 | **0.16** | **0.16** | 2.00 | 0.51 | 18.84 | 287.00 | 0 |
| no-match-rare-byte | **0.02** | **0.02** | **0.02** | **0.02** | 0.05 | 4.08 | 24.75 | 0 |
| word-boundary | 18.95 | **0.05** | **0.05** | **0.05** | 0.08 | 5.05 | 145.47 | 26 |
| line-anchor | 11.92 | 0.07 | 0.07 | **0.06** | 0.09 | 5.35 | 40.41 | 0 |
| prefix-nullable | 34.89 | 2.03 | 2.05 | 2.95 | **2.00** | 160.23 | 249.04 | 856 |
| blank-lines | 16.48 | 2.09 | 2.11 | **0.64** | 2.09 | 9.90 | 51.39 | 2082, 2083 |
| optional-word | 75.61 | 15.33 | 17.54 | **7.96** | 19.94 | 29.83 | 152.47 | 462981, 462982, 463177, 612507, 612703 |
| trailing-space | 32.98 | **0.00** | **0.00** | 3.88 | **0.00** | 96.87 | 98.94 | 1, 2 |
| empty-word-edges | 49.49 | 11.76 | 13.82 | **6.49** | 15.46 | 47.44 | 221.13 | 299052, 438128 |
| empty-line-ends | 15.25 | 1.91 | 2.01 | **1.50** | 3.28 | 25.16 | 39.26 | 26293 |

## Open

Not probed: whether Rust finds this pattern with the same inner-literal strategy (its docs describe a reverse-inner optimization; its
exact conditions were not read). The remaining gaps are the rows that match densely (`\w*`, `\b`, `(?m)$`: 1.2x to 1.6x), per-call
overhead on tiny haystacks (`literal`, `no-match-rare-byte`: about 2x), and Teddy verification.
