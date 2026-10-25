---
status: done
blocked-by: []
date: 2026-10-25
---

# 0006 — Close the gap with Rust's `regex`

The owner asked for this to be on the roadmap and **after** I-Regexp and Unicode. Standing (`docs/research/engine-comparison-2026-10.md`):
third; median 2.2x behind Rust per file. Each item below is a hypothesis with a measured row, to be probed before it is built, and kept
only if its row moves.

## The queue, by measured gap

1. **End-anchored patterns: done.** `[ \t]*$` went from 1.77 ms to 0.06 ms (about 30x; Rust 0.01 ms). A pattern whose every match must
   end at `\z` is searched backwards from the end by the reverse DFA, which reads only what the match covers. Whether Rust does exactly this
   was a hypothesis and was not checked; what is measured is that the row moved. What remains of the 0.06 ms is per-call overhead (item 4).
2. **An inner literal for captures.** `(\w+)\s*:\s*(\w+)\s*\{` is 4x behind. Search for a required literal, then run the reverse DFA.
3. **Dense empty matches.** `\w*` and `\b`: about 60 ns per match against about 35. A forward-only path when the start is known.
4. **Per-call overhead on small haystacks.** Literal 0.14 ms against 0.05: a non-allocating iteration API, a lock-free scratch fast path.
5. **Verification cost.** About 40% of the literal rows: Teddy with three bytes, or a rare-byte filter, to cut candidates.
6. **Native x86_64 timing** (roadmap 0014), because the C kernel's bar is met on arm64 only.

## Gate

The comparison rerun after each step; the row moved, or the step is reverted. The README keeps saying "third" until the table does not.

## State (2026-10-25, third run)

Done: end-anchored patterns (earlier), `matchCount` and `isMatch` without capture groups, and the terminal-byte jump (`captures` 2.51 to 0.46 ms,
now faster than Rust's 0.61 on that one row). Measurements and the one-step-at-a-time table: `docs/research/engine-comparison-2026-10-25.md`.
Open, in order: the dense-match rows (`\w*`, `\b`, `(?m)$`), per-call overhead on tiny haystacks, Teddy verification, class-trie merging for `\p{L}`,
and an RE2-style clear-and-continue when the DFA cache is full. Whether Rust uses the same strategy for `captures` is unprobed.

## Decision (2026-10-25)

Work on closing further micro-benchmarking gaps against Rust's `regex` crate is halted per user direction, to prioritize public API surface,
ergonomics, stability, and consumer integration (AemiJSON).

### Final Benchmark Result Summary

- End-anchored search: reverse DFA scan from the text end (`[ \t]*$` 1.77 ms to 0.04 ms).
- Match counting: avoids running the Pike VM for capture groups when only bounds are needed.
- Terminal-byte search: SIMD skip to single ending bytes (`captures` 2.63 ms to 0.46 ms, outperforming Rust's 0.61 ms).
- Overall: median 1.64x behind Rust ASCII per file across 14 workloads; 1 row faster than Rust, 5 rows faster than PCRE2 JIT, faster than
  Go, ICU (`NSRegularExpression`), and Swift `Regex` on all rows.
