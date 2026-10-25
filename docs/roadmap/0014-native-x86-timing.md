---
status: not-started
blocked-by: []
date: 2026-10-25
---

# 0014 — Native x86_64 timing

The C kernel's bar (ADR-0004) is met on arm64 only; x86_64 is checked for correctness under Rosetta. Run `Scripts/bench-compare.sh` and
the Teddy probe on an Intel or AMD host, with and without AVX2 considered, and revise ADR-0004 if the bar is not met there.
