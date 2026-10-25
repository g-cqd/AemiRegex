---
status: done
blocked-by: []
date: 2026-10-25
---

# 0012 — Structure gates, and the first CI run

## Done

- `SourceStructureTests` (ADR-0010): one top-level type per file, named for it, 250-line cap, with no baseline.
- `RepositoryHygieneTests`: no build output, no files over 3 MB, no tokens or home-directory paths, and no work-marker words in Swift sources.
- `NoRecursionTests`: structural verification that no function in the library or tests reaches itself.
- GitHub Actions CI is fully functional and green: Linux (debug/release), macOS (debug/release), sanitizers (ASan, UBSan, TSan) running SSSE3
  natively on x86_64, static analyzers (deadwood, dolly, arcleak), Go fixture regeneration, and the consumer path.
