"""Esports first-map winners on Polymarket: how often Map/Game 1's winner takes a best-of-three series, how
often the series is swept 2-0, and what the series price at the start says about it.

Inputs, published beside this script:
  esports-map1-series.csv  the read-only export: 9,504 settled BO3 series (CS2, Valorant,
                                              Dota 2, LoL) with a settled Map/Game 1, Map/Game 2 and Games
                                              Total market on the same event, moneyline volume $100 or more
  esports-map1-prices.csv  each series' starting price (team0's), from the public CLOB

A series is left out of the pricing tables when its window returned no price, its price is more than 60
minutes from the match start, or it priced exactly 50-50. Three series (of 9,504) disagree across the
three-market settlement check (map 1 and map 2 winner against the series result and the Games Total market)
and are left out everywhere; they are printed below by event_slug.

  edge          the favorite's (or underdog's) win rate minus its average starting price, in percentage points
  flat return   the average profit of $1 staked on that side in every series at its starting price, in percent
  fee           Polymarket's sports taker fee, 0.05 x p x (1 - p) USDC a share, is 0.05 x (1 - p) on $1 at price p
Intervals resample series: 5,000 draws, seed 20260914. Rates carry a binomial 95% half-width.

For two evenly matched teams (each map an independent 50/50), the winner of map 1 goes on to win the series
3/4 of the time (0.5 + 0.5 x 0.5) and the series is swept 2-0 half the time (0.5 x 0.5 x 2). Those are the
baselines the headline rates are measured against.

Usage: python3 esports-map1-analysis.py
"""

import csv
from collections import defaultdict

import numpy as np

DRAWS = 5000
SEED = 20260914
Z = 1.959964
GAMES = (("cs2", "CS2"), ("dota2", "Dota 2"), ("lol", "LoL"), ("valorant", "Valorant"))
EVEN_TEAMS_MAP1_WINS_SERIES_PCT = 75.0
EVEN_TEAMS_SWEEP_PCT = 50.0

series = {row["condition_id"]: row for row in csv.DictReader(open("esports-map1-series.csv"))}
prices = {row["condition_id"]: row for row in csv.DictReader(open("esports-map1-prices.csv"))}


def rate(values):
    values = np.asarray(values, dtype=float)
    p = values.mean()
    return 100 * p, 100 * Z * np.sqrt(p * (1 - p) / len(values))


def bootstrap(statistic, *columns):
    arrays = [np.asarray(column, dtype=float) for column in columns]
    size = len(arrays[0])
    index = np.random.default_rng(SEED).integers(0, size, size=(DRAWS, size))
    return np.percentile(statistic(*[array[index] for array in arrays]), [2.5, 97.5])


# ---- Settlement cross-check and the counted universe -----------------------------------------------------
mismatches = []
rows = []
for condition_id, row in series.items():
    swept = row["swept"] == "t"
    same_map_winner = row["map1_winner"] == row["map2_winner"]
    if same_map_winner:
        ok = swept and row["series_winner"] == row["map1_winner"]
    else:
        ok = not swept
    if not ok:
        mismatches.append(row)
        continue
    rows.append({**row, "map1_won_series": int(row["map1_winner"] == row["series_winner"]), "swept": int(swept)})

print(f"== Settlement cross-check: {len(series)} series, {len(mismatches)} disagree, left out")
for row in mismatches:
    print(f"  {row['event_slug']:32} {row['team0']:24} {row['team1']:20} series={row['series_winner']:18} map1={row['map1_winner']:18} map2={row['map2_winner']:18} swept={row['swept']}")

print(f"\n== Counted universe: {len(rows)} series")
for key, name in GAMES:
    subset = [row for row in rows if row["game"] == key]
    first = min(row["game_start_utc"] for row in subset)[:10]
    last = max(row["game_start_utc"] for row in subset)[:10]
    volume = sum(float(row["volume_usd"]) for row in subset)
    print(f"{name:10} series {len(subset):5d}  {first} to {last}  volume ${volume:,.0f}")

# ---- Headline rates: first-map winner taking the series, and the sweep rate -------------------------------
print("\n== Map/Game 1 winner taking the series, and the sweep rate")
for key, name in list(GAMES) + [("all", "All four games")]:
    subset = [row for row in rows if key == "all" or row["game"] == key]
    won_pct, won_half = rate([row["map1_won_series"] for row in subset])
    swept_pct, swept_half = rate([row["swept"] for row in subset])
    print(
        f"{name:16} n {len(subset):5d}  map1 winner took series {won_pct:5.1f}% +/- {won_half:.2f}  "
        f"(even-teams baseline {EVEN_TEAMS_MAP1_WINS_SERIES_PCT:.0f}%)   swept {swept_pct:5.1f}% +/- {swept_half:.2f} "
        f"(even-teams baseline {EVEN_TEAMS_SWEEP_PCT:.0f}%)"
    )

# ---- Pricing: attach each series' starting price and side it out ------------------------------------------
left_out = defaultdict(int)
priced_rows = []
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
    favorite_price = team0_price if team0_is_favorite else 1 - team0_price
    favorite = row["team0"] if team0_is_favorite else row["team1"]
    favorite_won = int(row["series_winner"] == favorite)
    priced_rows.append({**row, "favorite_price": favorite_price, "favorite_won": favorite_won})

print(f"\n== Priced series: {len(priced_rows)} of {len(rows)}")
for reason, n in sorted(left_out.items()):
    print(f"  left out: {reason:42} {n}")


def side_row(label, subset, side):
    if not subset:
        print(f"{label:34} series     0")
        return
    fav_price = np.array([row["favorite_price"] for row in subset])
    fav_won = np.array([row["favorite_won"] for row in subset], dtype=float)
    price = fav_price if side == "favorite" else 1 - fav_price
    won = fav_won if side == "favorite" else 1 - fav_won
    pct, half = rate(won)
    edge = 100 * (won.mean() - price.mean())
    e_lo, e_hi = bootstrap(lambda w, p: 100 * (w.mean(axis=-1) - p.mean(axis=-1)), won, price)
    flat = 100 * np.mean(won / price - 1)
    f_lo, f_hi = bootstrap(lambda w, p: 100 * np.mean(w / p - 1, axis=-1), won, price)
    after = 100 * np.mean(won / price - 1 - 0.05 * (1 - price))
    a_lo, a_hi = bootstrap(lambda w, p: 100 * np.mean(w / p - 1 - 0.05 * (1 - p), axis=-1), won, price)
    print(
        f"{label:34} series {len(subset):5d}  {side:9} price {100 * price.mean():6.2f}c  won {pct:5.1f}% +/- {half:5.2f}  "
        f"edge {edge:+6.2f} [{e_lo:+.2f}, {e_hi:+.2f}]  flat {flat:+7.2f}% [{f_lo:+.2f}, {f_hi:+.2f}]  after_fee {after:+7.2f}% [{a_lo:+.2f}, {a_hi:+.2f}]"
    )


print("\n== Favorites and underdogs at the series starting price")
side_row("All four games: favorite", priced_rows, "favorite")
side_row("All four games: underdog", priced_rows, "underdog")
for key, name in GAMES:
    subset = [row for row in priced_rows if row["game"] == key]
    side_row(f"{name}: favorite", subset, "favorite")

print("\n== Favorites by starting price band, pooled across the four games")
bands = (("50c to 60c", 0.5, 0.6), ("60c to 70c", 0.6, 0.7), ("70c to 80c", 0.7, 0.8), ("80c to 90c", 0.8, 0.9), ("90c and up", 0.9, 1.01))
for label, lo, hi in bands:
    subset = [row for row in priced_rows if lo <= row["favorite_price"] < hi]
    side_row(f"Favorite {label}", subset, "favorite")

print("\n== Did the pre-match favorite also win Map/Game 1?")
for key, name in list(GAMES) + [("all", "All four games")]:
    subset = [row for row in priced_rows if key == "all" or row["game"] == key]
    fav_names = []
    for row in subset:
        p = prices[row["condition_id"]]
        team0_price = float(p["start_price"])
        fav_names.append(row["team0"] if team0_price > 0.5 else row["team1"])
    pct, half = rate([1 if row["map1_winner"] == fav else 0 for row, fav in zip(subset, fav_names)])
    print(f"{name:16} n {len(subset):5d}  favorite also won map/game 1: {pct:5.1f}% +/- {half:.2f}")
