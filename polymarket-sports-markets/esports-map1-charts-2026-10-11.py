"""Section charts for /research/esports-first-map-winner-polymarket (#23687, epic #23652).

Deterministic from the two committed inputs of the September 14 study, read beside this script:
  esports-map1-series.csv  9,504 settled best-of-three series and their map and totals results
  esports-map1-prices.csv  each series' starting price (team0's), from the public CLOB

The universe and the pricing rules are the September study's, unchanged
(esports-map1-analysis.py): the 3 series that fail the three-market settlement check are
left out everywhere, and a series is priced when its window returned a price no more than 60 minutes before
the listed start and not exactly 50-50. This script only cuts the same rows new ways:

  1. Counted series by calendar month (UTC, the listed start) and game.
  2. What Map/Game 1 did to the favorite: the favorite's series win rate after it took Map 1 and after it
     dropped Map 1, pooled, by game and by the favorite's starting-price band.
  3. The same from the underdog's side: how often an underdog that took Map 1 went on to win the series.
  4. How far before the listed start the starting price was read, for the priced series.

Rates carry a binomial 95% half-width (z = 1.959964), as in the September script.

Usage: python3 esports-map1-charts-2026-10-11.py
"""

import csv
from collections import Counter, defaultdict

import numpy as np

Z = 1.959964
GAMES = (("cs2", "CS2"), ("dota2", "Dota 2"), ("lol", "LoL"), ("valorant", "Valorant"))
BANDS = (("50c to 60c", 0.5, 0.6), ("60c to 70c", 0.6, 0.7), ("70c to 80c", 0.7, 0.8), ("80c to 90c", 0.8, 0.9), ("90c and up", 0.9, 1.01))

series = {row["condition_id"]: row for row in csv.DictReader(open("esports-map1-series.csv"))}
prices = {row["condition_id"]: row for row in csv.DictReader(open("esports-map1-prices.csv"))}


def rate(values):
    values = np.asarray(values, dtype=float)
    if len(values) == 0:
        return float("nan"), float("nan")
    p = values.mean()
    return 100 * p, 100 * Z * np.sqrt(p * (1 - p) / len(values))


# ---- The counted universe, exactly as the September script builds it --------------------------------------
rows = []
for row in series.values():
    swept = row["swept"] == "t"
    ok = (swept and row["series_winner"] == row["map1_winner"]) if row["map1_winner"] == row["map2_winner"] else not swept
    if ok:
        rows.append(row)
print(f"== Counted universe: {len(rows)} of {len(series)} series")

# ---- 1. Counted series by month and game -----------------------------------------------------------------
by_month = defaultdict(Counter)
for row in rows:
    by_month[row["game_start_utc"][:7]][row["game"]] += 1
print("\n== 1. Counted series by month (UTC, listed start) and game")
print(f"{'month':8} {'cs2':>6} {'dota2':>6} {'lol':>6} {'valorant':>9} {'total':>6}")
for month in sorted(by_month):
    counts = by_month[month]
    print(f"{month:8} {counts['cs2']:6d} {counts['dota2']:6d} {counts['lol']:6d} {counts['valorant']:9d} {sum(counts.values()):6d}")

# ---- Priced rows, exactly as the September script prices them ---------------------------------------------
left_out = Counter()
priced = []
for row in rows:
    price = prices.get(row["condition_id"])
    if price is None or price["start_price"] == "":
        left_out["no price in the 24h window"] += 1
        continue
    if float(price["minutes_before"]) > 60:
        left_out["price more than 60 minutes before start"] += 1
        continue
    team0_price = float(price["start_price"])
    if team0_price == 0.5:
        left_out["priced exactly 50-50"] += 1
        continue
    team0_is_favorite = team0_price > 0.5
    favorite = row["team0"] if team0_is_favorite else row["team1"]
    priced.append(
        {
            "game": row["game"],
            "favorite_price": team0_price if team0_is_favorite else 1 - team0_price,
            "favorite_won": int(row["series_winner"] == favorite),
            "favorite_won_map1": int(row["map1_winner"] == favorite),
            "minutes_before": float(price["minutes_before"]),
        }
    )
print(f"\n== Priced series: {len(priced)} of {len(rows)}")
for reason, n in sorted(left_out.items()):
    print(f"  left out: {reason:42} {n}")


def after_map1(label, subset):
    took = [r for r in subset if r["favorite_won_map1"] == 1]
    dropped = [r for r in subset if r["favorite_won_map1"] == 0]
    price = 100 * np.mean([r["favorite_price"] for r in subset])
    took_pct, took_half = rate([r["favorite_won"] for r in took])
    dropped_pct, dropped_half = rate([r["favorite_won"] for r in dropped])
    dog_pct, dog_half = rate([1 - r["favorite_won"] for r in dropped])
    print(
        f"{label:16} series {len(subset):5d}  favorite price {price:6.2f}c  "
        f"took map 1: {len(took):5d}, won series {took_pct:5.1f}% +/- {took_half:4.2f}   "
        f"dropped map 1: {len(dropped):5d}, won series {dropped_pct:5.1f}% +/- {dropped_half:4.2f}  "
        f"(underdog that took map 1 won the series {dog_pct:5.1f}%)"
    )


# ---- 2 and 3. What Map 1 did to the favorite -----------------------------------------------------------
print("\n== 2. The favorite's series win rate after it took or dropped Map/Game 1")
after_map1("All four games", priced)
for key, name in GAMES:
    after_map1(name, [r for r in priced if r["game"] == key])

print("\n== 3. The same, by the favorite's starting-price band, pooled across the four games")
for label, lo, hi in BANDS:
    after_map1(f"Favorite {label}", [r for r in priced if lo <= r["favorite_price"] < hi])

# ---- 4. How far before the listed start the price was read ------------------------------------------------
print("\n== 4. Minutes between the starting price's point and the listed start, priced series")
minutes = np.array([r["minutes_before"] for r in priced])
print(f"median {np.median(minutes):.2f}  p90 {np.percentile(minutes, 90):.2f}  max {minutes.max():.2f}")
edges = ((0, 1, "under 1 minute"), (1, 5, "1 to 5 minutes"), (5, 15, "5 to 15 minutes"), (15, 60.0001, "15 to 60 minutes"))
for lo, hi, label in edges:
    n = int(((minutes >= lo) & (minutes < hi)).sum())
    print(f"  {label:18} {n:5d}  {100 * n / len(minutes):5.1f}%")
