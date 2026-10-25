---
status: accepted
date: 2026-10-24
---

# 0005 — `unsafe` is confined, justified, and netted

## Context

Speed came from unchecked indexing in the DFA loops and from C, both of which read attacker-controlled bytes.

## Decision

The package builds with `StrictMemorySafety`, so every unsafe expression is marked. Unchecked indexing lives in `scanForward`,
`scanBackward`, `ByteScan`, `LiteralSet.firstMatch` and the C kernel, each with its invariants written above it. Each has these nets:

1. a **fail-closed check** on anything that crosses back from C (a position outside the buffer stops the program);
2. **debug assertions** inside the loops (and Swift's own bounds checks on `UnsafeBufferPointer` outside release);
3. **poisoned-tail tests**: bytes just past the buffer are made to complete a match, so an overread changes an answer;
4. **a scalar or bounds-checked reference** the fast path is compared with, on random and hostile bytes;
5. **ASan with UBSan, and TSan**, over C and Swift; the C kernel also x86_64 under Rosetta.

## Evidence

Mutation testing found three mutations that output tests did not catch the first time: a one-byte overread in the pair scan (an
overread inside an allocation changes no answer; a poisoned-tail test caught it), the same in the reverse DFA loop (invisible in
output; only debug builds and ASan see it), and an overrun of the candidate buffer (the test data never filled it; a dense-candidate
test caught it). All are now caught (diary 2026-10-24-01).

## Consequences

A new unsafe construct needs all five nets before it merges. A net that cannot fail is not counted.

## Update, 2026-10-25

Searches now take a borrowed buffer so strings and arrays are searched in place. The Pike VM, which is the bounds-checked reference, reads it
through `ByteBuffer`, declared `@safe` because its only read is a subscript that checks the index in release builds as well; the raw pointer
accessor stays `@unsafe`. The claim is tested by exit tests (a read one past the end, a negative read and a read of an empty buffer each must
kill the process) and by mutation (a bound loosened by 64 fails them). Marking the whole type `@unsafe` instead was tried and rejected: it put
an `unsafe` on every line of the reference engine without making it any less checked.

