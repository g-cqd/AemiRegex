---
status: accepted
date: 2026-10-29
---

# 0013 — The engine depends on Aemi for its kernels, UTF-8 reading, scratch pool and Unicode data

## Context

The engine had no package dependencies (white paper, "Dependencies"), so it carried its own byte scans, a C Teddy kernel (ADR-0004),
strict UTF-8 reading, a checked byte view, a byte bitmap, a sparse set, a scratch pool, UTF-8 range compilation and generated Unicode
tables (ADR-0009, ADR-0012). Aemi is the family this package belongs to and is for exactly these; some were duplicates of Aemi's (memchr,
the nibble-table set scan), and the Unicode data had a second user (AemiMarkdown). The owner asked for the general parts to move into Aemi
and for the engine to depend on it.

## Decision

The engine depends on Aemi (`AemiKernels`, `AemiKernel`, `AemiUnicode`, `AemiRuntime`) at the revision the family pins. Moved, with
their tests, into Aemi (aemi ADR 0018): the Teddy kernel (`AemiKernels.PairSet`), the pair and small-set scans, `UTF8Scalar`
(`Utf8`, `ScalarReader`), `CheckedBytes` (`ByteBuffer`), `ByteBitmap` (`ByteSet`), `SparseSet`, `UTF8RangeSequences`, `ScratchPool`,
`UnicodeScalarSet` (`ScalarSet`), the generated tables and their generators (`UnicodeData`, `CaseFolding.simpleOrbit`). The single-byte scan
is Aemi's memchr kernel. What stays is the engine: parsers, compilers, the Pike VM, the lazy DFA, the backtracker, the prefilter and
literal analysis, and the dialects' name rules (Go's loose names, PCRE2's spelling, I-Regexp's, the special names `Any`, `Assigned`,
`Ascii`). `CAemiRegex` and `Scripts/unicode` and `teddy-check` are gone; CI no longer regenerates the Unicode table (Aemi's CI does).

## Evidence

- The suite (golden tests against Go, differential tests, PCRE2 oracle fixtures): 170 tests pass; the 7 table tests moved to Aemi.
- AemiRegex's workloads over its own sources copied 20 times (18 MB), before and after, median of 15 rounds, three interleaved runs each,
  release, loaded machine; µs, match counts identical in every row:

```
workload             mode   before µs   after µs  ratio  counts
literal              files        944        762   0.81  same
literal              one          687        564   0.82  same
alternation          files       1771       1719   0.97  same
alternation          one         1558       1540   0.99  same
func-async           files       1537       1526   0.99  same
func-async           one         1343       1332   0.99  same
captures             files       1869       1030   0.55  same
captures             one         1625        888   0.55  same
case-insensitive     files       1292       1260   0.98  same
case-insensitive     one         1535       1439   0.94  same
no-match-rare-byte   files        771        479   0.62  same
no-match-rare-byte   one          498        240   0.48  same
word-boundary        files        888        883   0.99  same
word-boundary        one          674        672   1.00  same
line-anchor          files        824        807   0.98  same
line-anchor          one          612        611   1.00  same
prefix-nullable      files      11286      11135   0.99  same
prefix-nullable      one        11179      11036   0.99  same
blank-lines          files      23895      23442   0.98  same
blank-lines          one        23669      23243   0.98  same
optional-word        files     178221     170747   0.96  same
optional-word        one       182973     170509   0.93  same
trailing-space       files        181        176   0.97  same
trailing-space       one            0          0   0.00  same
empty-word-edges     files     144102     142551   0.99  same
empty-word-edges     one       147962     145908   0.99  same
empty-line-ends      files      30964      31068   1.00  same
empty-line-ends      one        30675      31024   1.01  same
```

  The first build regressed one-search-per-file rows by 1.3 to 3.4x (an unspecialized generic pool, then a run-time exclusivity check,
  then a C call where an inline loop was cheaper); each was fixed in Aemi, as aemi ADR 0018 records.

## Consequences

- The package joins the family's pin chain: an Aemi revision reaches this package first, then AemiJSON and AemiMarkdown, which pin both.
- A general piece found here belongs in Aemi, with its tests, written red first.
- ADR-0004's measured bar for C still holds; the kernel it admitted now lives in Aemi's C target.
