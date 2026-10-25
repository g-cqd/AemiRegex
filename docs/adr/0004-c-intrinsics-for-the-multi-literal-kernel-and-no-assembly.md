---
status: accepted
date: 2026-10-24
---

# 0004 — C intrinsics for the multi-literal kernel, and no assembly

## Context

The question was whether regex matching needs ARM NEON assembly. The first report (in `ask`) found a Swift SIMD byte scan within 0.3 ms of
`memchr` on sparse input and recommended against assembly or a C target, with a revisit bar: a Swift kernel losing to the best native code
by more than 2x on at least 100 MB.

## Decision

Single-byte, byte-pair and byte-set scans stay in Swift SIMD. The multi-literal "Teddy" kernel is C intrinsics (NEON `tbl`, SSSE3
`pshufb`, scalar fallback) in `Sources/CAemiRegex`, behind a Swift wrapper that checks every result. No hand-written assembly.

## Evidence

- Swift SIMD against C intrinsics on byte-extraction, 135 MB, four densities: Swift within 1.0 to 1.4x (diary 2026-10-24-01).
- Teddy, 100 MB, **both loops unrolled to 64 bytes**: C 16.9 GB/s against Swift 5.0 for five pairs (3.3x), 16.5 against 2.7 for twelve (6.1x).
  Swift SIMD cannot express a variable byte shuffle, so there is no Swift Teddy.
- **A first probe without unrolling showed 1.4 to 1.8x** and recommended no C. It was unfair: each iteration paid its horizontal-reduce
  latency. This ADR exists because a probe can be wrong in the direction that favours the simpler answer.
- End to end, alternation went from 3.83 ms to 0.63 and case-insensitive literals from 1.96 to 0.49.

## Consequences

The bar is met on arm64 only: x86_64 is checked for correctness under Rosetta (`Scripts/teddy-check.sh`) and not timed; roadmap 0014 owns
a native run. The C target is a second thing to audit; ADR-0005 says how.
