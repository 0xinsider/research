#!/usr/bin/env python3
"""Market-clustered bootstrap for the sports studies.

Trades in the same market are not independent. Resample markets, not trades.
    python3 bootstrap.py <csv> [<csv> ...]
Each CSV has a header and columns: group, condition_id, n, sum_edge.
"""
import csv, sys, collections
import numpy as np

DRAWS = 5000
SEED = 20260912

for path in sys.argv[1:]:
    groups = collections.defaultdict(list)
    with open(path) as fh:
        r = csv.reader(fh); next(r)
        for g, cid, n, s in r:
            groups[g].append((int(n), float(s)))
    print(f"\n== {path.rsplit('/',1)[-1]}  ({DRAWS} draws, seed {SEED}, resampled over markets)")
    print(f"{'group':26} {'trades':>7} {'markets':>8} {'edge_pts':>9}   95% CI")
    for g in sorted(groups):
        arr = np.array(groups[g], dtype=float)
        n, s = arr[:,0], arr[:,1]
        point = s.sum()/n.sum()*100
        rng = np.random.default_rng(SEED)
        idx = rng.integers(0, len(arr), size=(DRAWS, len(arr)))
        draws = s[idx].sum(axis=1)/n[idx].sum(axis=1)*100
        lo, hi = np.percentile(draws, [2.5, 97.5])
        print(f"{g:26} {int(n.sum()):7d} {len(arr):8d} {point:9.2f}   [{lo:+.2f}, {hi:+.2f}]")
