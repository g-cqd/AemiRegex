# Does a regex prefilter need NEON assembly? (2026-10-24)

**Question.** The `ask` report (`docs/research/aemiregex-requirements-2026-10.md` there) measured a Swift `SIMD16` byte scan against
`memchr` on sparse input only and concluded that assembly is not needed. It set a bar for revisiting: a Swift kernel that loses to the
best native code by **more than 2x on at least 100 MB, on both architectures**. NEON has no movemask instruction, so the open risk is
*candidate extraction* on dense input, not the compare. This probe tests that case.

**Setup (observed).** Apple M2 Pro, arm64 only, Swift 6.4, `clang -O3`, load average 10 to 13 (other agents running). Corpus: the `ask`
Swift sources repeated to 135 MB, in memory. Counting the positions of one byte, at four densities. Probe sources:
`docs/research/probes/neon-prefilter-*.txt`. Nine runs per cell, median shown.

| Variant | sparse `Q` (7k hits) | `f` (1.5M) | `e` (10M) | space (31M) |
|---|---|---|---|---|
| scalar loop | 54 ms | 61 | 143 to 223 | 168 |
| Swift `SIMD16`, lane loop on hit | 7.1 | 31 to 33 | 129 to 207 | 174 |
| Swift `SIMD16`, bit weights + `wrappedSum` | 6.4 to 6.9 | 18 to 20 | 68 to 71 | 101 to 117 |
| libc `memchr` loop | 4.4 to 4.9 | 28 to 46 | 154 to 165 | 330 to 420 |
| C intrinsics, `vshrn` nibble mask, 16 B | 4.8 | 16 to 37 | 61 to 68 | 107 to 133 |
| C intrinsics, `vshrn`, 64 B with OR-reduce reject | 3.9 to 5.0 | 18 to 46 | 56 to 59 | 98 to 133 |

**What this shows.**

1. The best Swift variant is within **1.0 to 1.4x** of C intrinsics in every cell where both ran under comparable load, far inside the 2x
   bar. On the two dense inputs the two are indistinguishable at this noise level.
2. The Swift lane loop (what the earlier report measured) is 2 to 3x slower than the best Swift variant on dense input. The loss is the
   extraction strategy, not the language: expressing the mask as bit weights and a horizontal add closes it without leaving Swift.
3. `memchr` is the slowest on dense input (it restarts per hit), so "call libc" is not a free upper bound.
4. Sparse input is the case that matters for a prefilter (the report measured a 99% reject rate), and there the gap between Swift and C is
   about 1.4x, in absolute terms 2 ms per 135 MB.

**Probe bug, found and fixed before these numbers.** The first C versions counted 4x too many hits, because a `vshrn` mask has four bits
per lane and `bits &= bits - 1` clears one. The counts disagreed with scalar; they now match in every row (7015, 1,493,158, 10,428,926,
30,608,641). Timings from the first run were discarded.

**Decision.** No assembly, and no C target, for the prefilter. Use the Swift bit-weight extraction. Compiler-generated code from
intrinsics is what hand assembly would be, so assembly can only win through instruction scheduling that clang misses; this probe gives
no sign of such a loss.

**Not measured, so not claimed.**
- x86_64 (SSE2, AVX2) timing; Rosetta results are correctness evidence only. The bar names both architectures, so this decision is
  provisional until a native host runs the probe.
- A multi-literal "Teddy" kernel (`tbl`-based nibble lookup). That is where NEON-specific code could pay off. It is not built.
- The effect on whole-regex time. Phase 1 of the engine has no prefilter; `docs/ROADMAP.md` gates the prefilter on the benchmark.
- A quiet machine. Rerun when the load is below 2; the ratios are more trustworthy than the absolute numbers.

**Revisit when** a multi-literal kernel exists in Swift and loses to a C or assembly version by more than 2x on 100 MB, natively on both
architectures.

## Update (2026-10-24, later): the decision above was wrong for multi-literal sets

The multi-literal ("Teddy") kernel this note names as the open case was probed with the loops unrolled to 64 bytes. C NEON intrinsics
(`vqtbl1q_u8`) ran at 16.5 to 16.9 GB/s against 2.7 to 5.0 GB/s for the best compare-based Swift SIMD version: 3.3x and 6.1x at 100 MB on
arm64. An earlier probe without unrolling had shown only 1.4 to 1.8x because both loops were latency-bound; it understated the gap.
Swift SIMD cannot express a variable byte shuffle (`tbl`, `pshufb`), so no Swift version of Teddy exists.

**Decision, revised:** `Sources/CAemiRegex` holds C intrinsics (NEON, SSSE3, scalar) for exactly this kernel, behind a Swift wrapper that
checks every result. Still no hand-written assembly: the intrinsics compile to what assembly would be. The single-byte, byte-pair and
byte-set scans stay in Swift (within 1.0 to 1.4x of C in the first probe). The x86_64 timing bar is **not met**: only correctness is
checked there (Rosetta). Details, the safety nets and the end-to-end effect: `engine-comparison-2026-10.md`.
