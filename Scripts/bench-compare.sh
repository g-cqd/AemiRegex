#!/bin/sh
# Runs AemiRegex, NSRegularExpression, Swift Regex, Go regexp, the Rust regex crate and PCRE2 (JIT) on one frozen corpus and one
# workload file, and prints a table of median milliseconds. Each engine counts matches per file over 9 rounds (3 for Swift Regex).
#
#   Scripts/bench-compare.sh [corpus-dir]        default: a snapshot of ../../ask/Sources taken now
#
# The corpus is copied to a temporary directory first: a live repository changes between runs. The harnesses are built into the
# temporary directory too. Needs go, cargo (offline, regex 1.12.3 in the local registry) and pcre2 (pcre2-config).
# Comparison caveats are printed with the table: a pattern that can match empty is counted differently by different engines.
set -eu
cd "$(dirname "$0")/.."
WORK="${TMPDIR:-/tmp}/aemiregex-bench"
rm -rf "$WORK" && mkdir -p "$WORK/corpus"
SRC="${1:-../../ask/Sources}"
(cd "$SRC" && find . -name '*.swift' | sort | while read -r f; do mkdir -p "$WORK/corpus/$(dirname "$f")" && cp "$f" "$WORK/corpus/$f"; done)
printf 'corpus: %s files, %s bytes (snapshot of %s)\n' "$(find "$WORK/corpus" -name '*.swift' | wc -l | tr -d ' ')" \
    "$(find "$WORK/corpus" -name '*.swift' -exec cat {} + | wc -c | tr -d ' ')" "$SRC"
W=Benchmarks/Comparison/workloads.tsv
(cd Benchmarks/Comparison/go && go build -o "$WORK/bench-go" .)
(cd Benchmarks/Comparison/rust && CARGO_TARGET_DIR="$WORK/rust-target" cargo build --release --offline --quiet)
cc -O2 -o "$WORK/bench-pcre2" Benchmarks/Comparison/pcre2/bench.c $(pcre2-config --cflags --libs8)
AEMIREGEX_DEV=1 swift build -c release --product AemiRegexBench --quiet
run_all() {
    "$WORK/bench-go" "$W" "$WORK/corpus"
    "$WORK/rust-target/release/bench" "$W" "$WORK/corpus"
    "$WORK/bench-pcre2" "$W" "$WORK/corpus"
    AEMIREGEX_DEV=1 swift run -c release AemiRegexBench --csv "$W" "$WORK/corpus" 2>/dev/null
}
echo; echo "### One haystack per file (what a search tool does): per-call overhead included"
run_all > "$WORK/per-file.csv"
python3 Scripts/bench-table.py "$WORK/per-file.csv" "$W"
echo; echo "### One 1 MB haystack: scan speed with per-call overhead removed"
CONCAT=1 run_all > "$WORK/one-buffer.csv"
python3 Scripts/bench-table.py "$WORK/one-buffer.csv" "$W"
