#!/usr/bin/env python3
"""Recompute every 95% interval in results.md from cluster_stats.csv, with no database access.

    python3 intervals.py

cluster_stats.csv holds, per design, grade bucket and clustering (market or wallet), the number
of clusters k, buys n, S = sum(won - price), and the cluster sums of s^2, s*n and n^2. The edge
is S / n. The cluster-robust variance of that ratio is
k / (k - 1) * (sum s^2 - 2e sum s*n + e^2 sum n^2) / n^2, and the reported half-width is 1.96
standard errors, the wider of the market and the wallet clustering.
"""

import collections
import csv
import math

by_key = collections.defaultdict(dict)
order = []
with open("cluster_stats.csv") as fh:
    for r in csv.DictReader(fh):
        key = (r["design"], r["bucket"])
        if key not in by_key:
            order.append(key)
        by_key[key][r["cluster"]] = {c: float(r[c]) for c in ("k", "n", "s", "ss", "sn", "nn")}

print("design|bucket|buys|edge_pts|ci_half|lo|hi")
for key in order:
    widths = []
    for m in by_key[key].values():
        e = m["s"] / m["n"]
        v = m["k"] / max(m["k"] - 1, 1) * (m["ss"] - 2 * e * m["sn"] + e * e * m["nn"]) / m["n"] ** 2
        widths.append(1.96 * math.sqrt(max(v, 0.0)))
    m = next(iter(by_key[key].values()))
    e, ci = m["s"] / m["n"], max(widths)
    print(f"{key[0]}|{key[1]}|{int(m['n'])}|{100 * e:+.2f}|{100 * ci:.2f}|{100 * (e - ci):+.2f}|{100 * (e + ci):+.2f}")
