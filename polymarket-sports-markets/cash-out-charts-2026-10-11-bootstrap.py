#!/usr/bin/env python3
"""Market-level bootstrap by sport and by month for /research/cashing-out-polymarket-sports (#23679).

The study (cash-out-2026-10-10*) did not bootstrap its sport and month cuts. The October 11 run
(cash-out-charts-2026-10-11.sql) exported them market by market. Its universe holds
one market more than the October 10 run, a soccer market settled after that run's fork with 18 June sells, so
this script keeps only the markets in the October 10 export's 'all sells' group. The point estimates it prints
then equal the October 10 run's queries 6 and 10 exactly.

    python3 cash-out-charts-2026-10-11-bootstrap.py \
        cash-out-2026-10-10-market-edge.csv cash-out-charts-2026-10-11-market-edge.csv

Same method as bootstrap-2026-09-13.py: 5,000 draws, seed 20260913, markets resampled within each
group. edge_pts is value given up (won minus price), the query sign; the article negates it (exit edge).
"""
import collections
import csv
import sys

import numpy as np

DRAWS = 5000
SEED = 20260913

october10, october11 = sys.argv[1], sys.argv[2]
with open(october10) as fh:
    keep = {row["condition_id"] for row in csv.DictReader(fh) if row["grp"] == "all sells"}

groups = collections.defaultdict(list)
dropped = collections.Counter()
with open(october11) as fh:
    for row in csv.DictReader(fh):
        if row["condition_id"] not in keep:
            dropped[(row["grp"], row["condition_id"])] += int(row["n"])
            continue
        groups[row["grp"]].append((int(row["n"]), float(row["sum_edge"])))

print(f"kept the {len(keep)} markets of the October 10 run; dropped {len({c for _, c in dropped})} market(s):")
for (group, condition_id), sells in sorted(dropped.items()):
    print(f"  {group}: {condition_id} ({sells} sells)")
print(f"\n== by sport and month  ({DRAWS} draws, seed {SEED}, resampled over markets)")
print(f"{'group':26} {'trades':>7} {'markets':>8} {'edge_pts':>9}   95% CI")
for group in sorted(groups):
    arr = np.array(groups[group], dtype=float)
    n, s = arr[:, 0], arr[:, 1]
    point = s.sum() / n.sum() * 100
    rng = np.random.default_rng(SEED)
    idx = rng.integers(0, len(arr), size=(DRAWS, len(arr)))
    draws = s[idx].sum(axis=1) / n[idx].sum(axis=1) * 100
    lo, hi = np.percentile(draws, [2.5, 97.5])
    print(f"{group:26} {int(n.sum()):7d} {len(arr):8d} {point:9.2f}   [{lo:+.2f}, {hi:+.2f}]")
