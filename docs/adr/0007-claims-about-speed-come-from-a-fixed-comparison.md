---
status: accepted
date: 2026-10-24
---

# 0007 — Claims about speed come from a fixed comparison

## Context

"Beats ICU" was met, and then the owner asked for a comparison with Go, Rust and the fastest known engine. The honest answer was "third".

## Decision

`Scripts/bench-compare.sh` is the one place numbers come from: a frozen corpus, one harness per engine (AemiRegex, ICU, Swift `Regex`, Go
`regexp`, Rust `regex` ASCII bytes and Unicode str, PCRE2 with JIT), the same workload file, median of nine rounds, in two modes (one
haystack per file, and one 1 MB buffer) so per-call overhead and scan speed can be told apart. Match counts are printed; where engines
disagree because of empty-match or Unicode rules the row says so, and speed is compared without the counts.

The README and every document say what the table says: AemiRegex is third. A change is kept only if its row moves; profiles
(`/usr/bin/sample`) locate the cost before a change is made.

## Evidence

The standing moved from a median 3.8x behind Rust to 2.2x in one day, through changes each located by a profile; three plausible causes
were wrong (diary 2026-10-24-01).

## Consequences

RE2, Hyperscan and Vectorscan are not installed here and are not claimed about. Numbers are one machine, one architecture, a loaded host.
