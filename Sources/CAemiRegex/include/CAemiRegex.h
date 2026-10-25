#ifndef CAEMIREGEX_H
#define CAEMIREGEX_H

#include <stddef.h>
#include <stdint.h>

/// The size in bytes of a Teddy table: the low-nibble and high-nibble lookup tables (16 bytes each) of the first byte and then of
/// the second byte of a pair. Entry `n` of a table is a bitmask of the buckets (0 to 7) that contain a pair whose byte has nibble `n`.
#define AEMIRE_TEDDY2_TABLE_BYTES 64

/// The index of the first position `i >= from` with `i + 1 < len` where both bytes of `hay[i], hay[i + 1]` are accepted by some common
/// bucket of `table`, or `SIZE_MAX` when there is none. A position is a candidate, not a certain pair: pairs that share a bucket can
/// produce a position that is no pair. A real pair is never skipped.
///
/// Uses NEON on arm64 and SSSE3 on x86_64 when the CPU has it; otherwise the scalar reference. Reads `hay[0 ..< len]` only.
size_t aemire_teddy2_find(const uint8_t *table, const uint8_t *hay, size_t len, size_t from);

/// The scalar reference of ``aemire_teddy2_find``: the same candidates, found one byte at a time. For tests.
size_t aemire_teddy2_find_scalar(const uint8_t *table, const uint8_t *hay, size_t len, size_t from);

/// Writes every candidate position (as in ``aemire_teddy2_find``) from `from` on into `out`, in ascending order, at most `cap` of
/// them, and returns how many it wrote. `*resume` is where to continue: every candidate before it is written, none at or after it is.
/// When `*resume >= len` the scan is complete. The scan stops early, before a block that might not fit, and always makes progress
/// (`*resume > from`, or `*resume >= len`) when `cap >= 1`; a `cap` under 16 uses the slower scalar path. Writes only `out[0 ..< cap]`; reads only `hay[0 ..< len]`.
size_t aemire_teddy2_candidates(
    const uint8_t *table, const uint8_t *hay, size_t len, size_t from, size_t *out, size_t cap, size_t *resume);

#endif
