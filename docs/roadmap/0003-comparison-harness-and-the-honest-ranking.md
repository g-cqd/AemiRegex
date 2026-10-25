---
status: done
blocked-by: ["0002"]
date: 2026-10-24
---

# 0003 — The comparison harness and the honest ranking

`Scripts/bench-compare.sh` and `Benchmarks/Comparison/`: Go, Rust `regex`, PCRE2 JIT, ICU, Swift Regex and AemiRegex on a frozen corpus,
per file and on one buffer. ADR-0007. `docs/research/engine-comparison-2026-10.md` has the tables.

## Done

AemiRegex is **third**: median 2.2x behind Rust per file (1.6x on one buffer), 2.2x behind PCRE2-JIT (wins 5 of 14 rows), faster than Go
on 13 of 14 and than ICU on all. Closing the Rust gap is roadmap 0006.
