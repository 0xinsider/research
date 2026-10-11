"""Section charts for /research/point-spreads-polymarket (#23663, epic #23652).

The final margin of every NFL game with a settled Polymarket moneyline, from ESPN's final score. No new read: the input
is the ESPN match published with the football underdogs study.

  football-scoreboard.csv   each settled NFL and college football moneyline matched to ESPN's final
                                              score, season type and venue (football-scoreboard.py)

A game counts once (by ESPN game id) when ESPN lists it as a regular-season or postseason game (season type 2 or 3).
The margin is the winner's points minus the loser's. NFL spreads on Polymarket are half-point lines, so a margin of
exactly N points decides every -(N - 0.5) and -(N + 0.5) line between them.

Usage: python3 spreads-nfl-margins-2026-10-11.py
"""

import csv
from collections import Counter

margins = Counter()
seen = set()
first = last = None
for row in csv.DictReader(open("football-scoreboard.csv")):
    if row["league"] != "nfl" or not row["espn_id"] or row["season_type"] not in ("2", "3"):
        continue
    if row["espn_id"] in seen:
        continue
    seen.add(row["espn_id"])
    margins[abs(int(row["away_score"]) - int(row["home_score"]))] += 1
    start = row["espn_start_utc"][:10]
    first = start if first is None or start < first else first
    last = start if last is None or start > last else last

games = sum(margins.values())
print(f"== NFL final margins: {games} regular-season and postseason games, {first} to {last} (ESPN start, UTC)")
print(f"ties {margins[0]}")
for margin in range(1, 22):
    print(f"margin {margin:2d}  games {margins[margin]:4d}  share {100 * margins[margin] / games:5.1f}%")
over = sum(number for margin, number in margins.items() if margin > 21)
print(f"margin 22+ games {over:4d}  share {100 * over / games:5.1f}%")
for line in (2.5, 3.5, 6.5, 7.5):
    covered = sum(number for margin, number in margins.items() if margin > line)
    print(f"won by more than {line}: {covered} games, {100 * covered / games:.1f}% of all games")
