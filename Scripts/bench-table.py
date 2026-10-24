#!/usr/bin/env python3
"""Turns `engine,workload,median_ms,count` rows into a table: one row per workload, one column per engine, the fastest in bold."""
import csv, sys
rows = list(csv.reader(open(sys.argv[1])))
order = [line.split("\t")[0] for line in open(sys.argv[2]).read().splitlines()]
engines = []
cell = {}
for engine, workload, ms, count in rows:
    if engine not in engines:
        engines.append(engine)
    cell[(engine, workload)] = (float(ms), int(count))
print("| workload | " + " | ".join(engines) + " | matches |")
print("|---|" + "---|" * (len(engines) + 1))
for w in order:
    present = {e: cell[(e, w)] for e in engines if (e, w) in cell}
    best = min(v[0] for v in present.values())
    counts = sorted({v[1] for v in present.values()})
    cells = []
    for e in engines:
        if e not in present:
            cells.append("-")
            continue
        ms = present[e][0]
        cells.append(f"**{ms:.2f}**" if ms == best else f"{ms:.2f}")
    print(f"| {w} | " + " | ".join(cells) + f" | {', '.join(map(str, counts))} |")
