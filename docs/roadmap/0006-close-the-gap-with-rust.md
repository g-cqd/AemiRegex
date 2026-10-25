---
status: not-started
blocked-by: []
date: 2026-10-25
---

# 0006 — Close the gap with Rust's `regex`

The owner asked for this to be on the roadmap and **after** I-Regexp and Unicode. Standing (`docs/research/engine-comparison-2026-10.md`):
third; median 2.2x behind Rust per file. Each item below is a hypothesis with a measured row, to be probed before it is built, and kept
only if its row moves.

## The queue, by measured gap

1. **End-anchored patterns.** `[ \t]*$`: Rust 0.01 ms, 1.77 here (177x). Probably a search from the end; confirm by reading Rust's
   documentation and then by a probe.
2. **An inner literal for captures.** `(\w+)\s*:\s*(\w+)\s*\{` is 4x behind. Search for a required literal, then run the reverse DFA.
3. **Dense empty matches.** `\w*` and `\b`: about 60 ns per match against about 35. A forward-only path when the start is known.
4. **Per-call overhead on small haystacks.** Literal 0.14 ms against 0.05: a non-allocating iteration API, a lock-free scratch fast path.
5. **Verification cost.** About 40% of the literal rows: Teddy with three bytes, or a rare-byte filter, to cut candidates.
6. **Native x86_64 timing** (roadmap 0014), because the C kernel's bar is met on arm64 only.

## Gate

The comparison rerun after each step; the row moved, or the step is reverted. The README keeps saying "third" until the table does not.
