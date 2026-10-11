"""Section charts for /research/football-underdogs-polymarket (#23663, epic #23652).

Two cuts the study's tables do not print, computed from files already published beside this script. No new
read: every input is a committed export.

  football-upsets-games-2026-10-10.csv     the 1,193 counted games (football-upsets-analysis-2026-10-10.py)
  football-games.csv            the settled-moneyline export
  football-scoreboard.csv       the ESPN match
  football-prices.csv           the kickoff prices
  football-pregame-volume-2026-10-10.csv   dollars traded on each moneyline before the cutoff

1. Underdogs by season: the underdog's average kickoff price and how often it won, per league and football
   season (a season runs from July to the next June; the 2026 seasons are their opening weeks to September 13).
2. Dollars traded before kickoff, in bands, over the analysis's first cut: every game that passes the September rule
   except the $10,000 floor (ESPN-listed regular-season or postseason game, settlement names ESPN's winner, a price
   within 60 minutes of the cutoff, not priced exactly 50-50). That is the 569 NFL and 1,035 college games the floor
   is applied to; the floor keeps 562 and 631.

Usage: python3 football-charts-2026-10-11.py
"""

import csv
import statistics
from collections import defaultdict

LEAGUES = (("nfl", "NFL"), ("cfb", "College football"))
BANDS = (
    ("under $1,000", 0, 1_000),
    ("$1,000 to $10,000", 1_000, 10_000),
    ("$10,000 to $50,000", 10_000, 50_000),
    ("$50,000 to $250,000", 50_000, 250_000),
    ("$250,000 to $1 million", 250_000, 1_000_000),
    ("$1 million or more", 1_000_000, float("inf")),
)


def season(game_start_utc):
    year, month = int(game_start_utc[:4]), int(game_start_utc[5:7])
    return year if month >= 7 else year - 1


counted = list(csv.DictReader(open("football-upsets-games-2026-10-10.csv")))
print(f"== 1. Underdogs by league and season ({len(counted)} counted games)")
by_season = defaultdict(list)
for row in counted:
    by_season[(row["league"], season(row["game_start_utc"]))].append(row)
for league, name in LEAGUES:
    for (key_league, year), rows in sorted(by_season.items()):
        if key_league != league:
            continue
        price = 100 * statistics.mean(1 - float(row["favorite_price"]) for row in rows)
        won = 100 * statistics.mean(1 - int(row["favorite_won"]) for row in rows)
        first = min(row["game_start_utc"] for row in rows)[:10]
        last = max(row["game_start_utc"] for row in rows)[:10]
        print(
            f"{name:17} season {year}  games {len(rows):4d}  underdog price {price:6.2f}c  won {won:5.1f}%  "
            f"won minus price {won - price:+6.2f}  {first} to {last}"
        )

games = {row["condition_id"]: row for row in csv.DictReader(open("football-games.csv"))}
scoreboard = {row["condition_id"]: row for row in csv.DictReader(open("football-scoreboard.csv"))}
prices = {row["condition_id"]: row for row in csv.DictReader(open("football-prices.csv"))}
pregame = {row["condition_id"]: row for row in csv.DictReader(open("football-pregame-volume-2026-10-10.csv"))}

first_cut = defaultdict(list)
for condition_id, game in games.items():
    board = scoreboard[condition_id]
    price = prices[condition_id]
    if not board["espn_id"] or board["season_type"] not in ("2", "3") or board["winner_agrees"] != "1":
        continue
    if price["kickoff_price"] == "" or float(price["minutes_before"]) > 60:
        continue
    if float(price["kickoff_price"]) == 0.5:
        continue
    first_cut[game["league"]].append(float(pregame[condition_id]["pregame_usd"]))

print("\n== 2. Dollars traded on the moneyline before kickoff, first cut (before the $10,000 floor)")
for league, name in LEAGUES:
    values = first_cut[league]
    kept = sum(1 for value in values if value >= 10_000)
    print(f"{name:17} games {len(values):5d}  median ${statistics.median(values):,.2f}  $10,000 or more {kept:5d}")
    for label, low, high in BANDS:
        number = sum(1 for value in values if low <= value < high)
        print(f"  {label:24} {number:5d}")
