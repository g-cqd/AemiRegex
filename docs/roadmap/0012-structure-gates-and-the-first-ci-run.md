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

- **The first CI run.** The repository was pushed (`g-cqd/aemiregex`, public) and the workflow started on 2026-10-25; its result has not
  been read. The workflow was written locally and never executed before that, so a red run is expected and its first failure is the
  work: the shared Aemi workflow's inputs, the dev dependency on `Aemi-Studio/aemi`, and the Go fixture-regeneration jobs are all
  unverified. Read it with `gh run list` and `gh run view --log-failed`.
- **The local pre-push hook skips tests** until `project-hooks trust` is run in this repository; it ran lint only.
