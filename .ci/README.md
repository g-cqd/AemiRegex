# CI runtime exceptions

`probes/FoundationRegexLeak.swift` reproduces the Linux Swift 6.4.1 Foundation
regex allocation leak without importing AemiRegex. A 300-character ASCII pattern
leaks its 600-byte UTF-16 buffer in `_CFRegularExpressionCreate`; the full seeded
Foundation-only differential workload reproduces precisely 510,838 bytes in 691
allocations from the first Actions run.

`swift.linuxLeakSuppressions` excludes allocations with that Foundation symbol
on their stack, not arbitrary AemiRegex allocations. It is Linux-ASan-only;
remove it when the supported Foundation runtime fixes the leak. The differential
oracle still runs all 10,000 comparisons under ASan. Other leak detection stays
on. Prefilter test-case data is built per request rather than retained in a
process-lifetime static heap allocation, and constructed inside the test body
rather than retained as nested parameter payloads by Swift Testing.
