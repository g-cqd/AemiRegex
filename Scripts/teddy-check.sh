#!/bin/sh
# Builds the Teddy kernel check for the host architecture and, on Apple silicon, also for x86_64 (run under Rosetta) so the SSSE3 path
# is exercised. Exit status is the check's.
set -eu
cd "$(dirname "$0")"
OUT="${TMPDIR:-/tmp}/aemiregex-teddy-check"
mkdir -p "$OUT"
cc -O2 -I../Sources/CAemiRegex/include -fsanitize=address,undefined -o "$OUT/check-host" teddy-check.c ../Sources/CAemiRegex/teddy.c
echo "host ($(uname -m)), ASan+UBSan:"; "$OUT/check-host"
if [ "$(uname -s)-$(uname -m)" = "Darwin-arm64" ]; then
    cc -O2 -I../Sources/CAemiRegex/include -arch x86_64 -fsanitize=address,undefined -o "$OUT/check-x86" teddy-check.c ../Sources/CAemiRegex/teddy.c 2>/dev/null \
        || cc -O2 -I../Sources/CAemiRegex/include -arch x86_64 -o "$OUT/check-x86" teddy-check.c ../Sources/CAemiRegex/teddy.c
    echo "x86_64 under Rosetta (SSSE3):"; arch -x86_64 "$OUT/check-x86"
fi
