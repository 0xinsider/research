"""#22294: the corrected over/under buy-level edges with intervals that resample games, not markets.

The same bootstrap as the last section of over-under-by-game.py (5,000 draws, seed 20260913), on
over-under-game-edge-2026-10-10.csv, which over-under-game-edge-2026-10-10.sql writes from the corrected
run's market-level export. Point estimates equal the corrected run's own; only the intervals change.
Usage: python3 over-under-game-bootstrap-2026-10-10.py
"""

import csv
from collections import defaultdict

import numpy as np

DRAWS = 5000
SEED = 20260913

groups = defaultdict(list)
for row in csv.DictReader(open("over-under-game-edge-2026-10-10.csv")):
    groups[row["grp"]].append((int(row["n"]), float(row["sum_edge"])))
print(f"{'group':26} {'trades':>7} {'games':>6} {'edge_pts':>9}   95% CI")
for group in sorted(groups):
    arr = np.array(groups[group], dtype=float)
    n, s = arr[:, 0], arr[:, 1]
    point = 100 * s.sum() / n.sum()
    rng = np.random.default_rng(SEED)
    picks = rng.integers(0, len(arr), size=(DRAWS, len(arr)))
    draws = 100 * s[picks].sum(axis=1) / n[picks].sum(axis=1)
    low, high = np.percentile(draws, [2.5, 97.5])
    print(f"{group:26} {int(n.sum()):7d} {len(arr):6d} {point:9.2f}   [{low:+.2f}, {high:+.2f}]")
