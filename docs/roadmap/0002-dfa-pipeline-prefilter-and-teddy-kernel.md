---
status: done
blocked-by: ["0001"]
date: 2026-10-24
---

# 0002 — The DFA pipeline, the prefilter, and the Teddy kernel

Forward lazy DFA (leftmost-first end) and reverse DFA (start), assertions resolved by the next byte, the Pike VM only for captures, a
literal prefilter (byte, pair, pair set, byte set), a literal matcher for pure alternations of fixed strings, and a C Teddy kernel driven in
byte windows.

## Done

The ICU gate (`SpeedGateTests`): faster than ICU on every workload with equal counts. ASan, UBSan, TSan, debug assertions and the x86_64
SSSE3 path under Rosetta all clean. ADR-0004, ADR-0005. Diary 2026-10-24-01 has the probes, the three wrong causes and the mutations.
