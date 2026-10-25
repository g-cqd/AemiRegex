---
status: in-progress
blocked-by: []
date: 2026-10-25
---

# 0012 — Structure gates, and the first CI run

## Done

`SourceStructureTests` (ADR-0010): one top-level type per file, named for it, and 250 lines, with no baseline because the nine violations
were fixed (`LazyDFA`, `Pattern`, `IRegexp` and their tests split; `SearchScratch`, `Instruction`, `Utf8Sequences` and two fixtures
separated into one file per type). Broken on purpose two ways; both fire.

## Still open

- **The first CI run was read; its fixes are pushed, the next run is unread.** First run (commit `3eb0b3b`): passed the Go fixture
  regeneration (all five generators reproduce their committed output), Linux release, Linux debug, the static analyzers, and the Linux
  **sanitizers (ASan, UBSan, TSan) on x86_64, which ran the C kernel's SSSE3 path natively** (correctness only; no timing). Failed: the
  shared workflow's tag check, because a benchmark-corpus string contained the word the family bans in Swift sources (fixed, and the same
  rule now runs locally in `RepositoryHygieneTests`). That failure skipped every job that depends on the gate: the **macOS legs, DocC
  and the consumer path have therefore never run**. Next: read the run for the fix and the macOS results (`gh run list`,
  `gh run view --log-failed`).
- **The local pre-push hook skips tests** until `project-hooks trust` is run in this repository; it ran lint only.
