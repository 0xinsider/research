#!/usr/bin/env python3
"""Market-clustered bootstrap for the grade-vs-price study.

Trades in the same market are not independent observations. Resampling markets
rather than trades keeps the interval honest.

    psql "$DATABASE_URL" -X -f queries.sql -qAt -F',' > market_edge.csv   # query 6
    python3 bootstrap.py
"""

import collections
import csv
import random

DRAWS = 5000
SEED = 20260912

rows = collections.defaultdict(list)
with open("market_edge.csv") as fh:
    reader = csv.reader(fh)
    header = next(reader)
    if header[0] != "cohort":  # psql -qAt emits no header; the published copy has one
        reader = csv.reader([",".join(header)] + [line for line in fh])
    for cohort, condition_id, n, sum_edge in reader:
        rows[cohort].append((int(n), float(sum_edge)))

random.seed(SEED)
print(f"{'cohort':10} {'trades':>7} {'markets':>8} {'edge_pts':>9}   95% CI")
for cohort in ("S/A/B", "C", "D/F", "no grade"):
    markets = rows[cohort]
    trades = sum(n for n, _ in markets)
    point = sum(s for _, s in markets) / trades * 100

    draws = []
    for _ in range(DRAWS):
        sample = [markets[random.randrange(len(markets))] for _ in range(len(markets))]
        draws.append(sum(s for _, s in sample) / sum(n for n, _ in sample) * 100)
    draws.sort()
    lo, hi = draws[int(0.025 * DRAWS)], draws[int(0.975 * DRAWS)]

    print(f"{cohort:10} {trades:7d} {len(markets):8d} {point:9.2f}   [{lo:+.2f}, {hi:+.2f}]")
