"""Recount home win rates for the home advantage study with ESPN's home team, season type and venue.

Input: home-espn-check.csv, the output of home-espn-check.py over the study's game universe
(one settled full-game moneyline per event, the first outcome read as the away team).
A game counts when:
  - ESPN lists a completed game between the two teams within 6 hours of the market's listed start, or within
    24 hours when it is the only completed game between them in the three-day window (Polymarket listed some
    games at a midnight placeholder: every NFL game of 2025-01-05 at 05:00 UTC);
  - it is a regular-season, postseason or play-in game (ESPN season type 2, 3 or 5), not a preseason or spring
    training game, an All-Star exhibition or a summer league game (those have no match or type 1);
  - ESPN does not mark it a neutral site;
  - the market's settlement names the team ESPN scores as the winner;
  - it is the first market for that ESPN game (a second event for the same game, such as a "-v2" slug, is
    left out).
The home team is ESPN's home team, whichever outcome Polymarket listed first.

Output: the tables below on stdout, and home-advantage-counted-games.csv (one row per counted game).
Usage: python3 home-espn-recount.py home-espn-check.csv home-advantage-counted-games.csv
"""

import csv
import math
import sys
from collections import Counter, defaultdict

Z = 1.959964
LEAGUES = ("nba", "nhl", "mlb", "wnba", "nfl", "cfb")


def rate(values):
    p = sum(values) / len(values)
    return 100 * p, 100 * Z * math.sqrt(p * (1 - p) / len(values))


def count_games(rows):
    """The counting rule above: (counted rows with `home_team` and `home_won`, left-out reasons)."""
    reasons = Counter()
    seen_games = set()
    counted = []
    for row in rows:
        league = row["league"]
        if not row["espn_id"]:
            reasons[(league, "no ESPN match")] += 1
            continue
        hours = float(row["hours_from_start"])
        if hours > 24 or (hours > 6 and row["final_candidates"] != "1"):
            reasons[(league, "nearest ESPN game is another game of the series")] += 1
            continue
        if row["season_type"] not in ("2", "3", "5"):
            reasons[(league, "preseason or spring training")] += 1
            continue
        if row["neutral_site"] == "1":
            reasons[(league, "neutral site")] += 1
            continue
        if row["winner_agrees"] != "1":
            reasons[(league, "settlement disagrees with ESPN's score")] += 1
            continue
        if row["espn_id"] in seen_games:
            reasons[(league, "second market for the same ESPN game")] += 1
            continue
        seen_games.add(row["espn_id"])
        first_named_won = row["winning_outcome"] == "0"
        first_named_is_away = row["away_is_away"] == "1"
        home_won = (not first_named_won) if first_named_is_away else first_named_won
        counted.append({
            **row,
            "home_team": row["home"] if first_named_is_away else row["away"],
            "home_outcome_index": 1 if first_named_is_away else 0,
            "home_won": int(home_won),
        })
    return counted, reasons


def main(input_path, output_path):
    rows = list(csv.DictReader(open(input_path)))
    counted, reasons = count_games(rows)

    print("== Left out, by league and reason")
    for (league, reason), number in sorted(reasons.items()):
        print(f"{league:5} {reason:52} {number:5d}")

    print("\n== Home win rate by league (ESPN home team, regular season and postseason, no neutral sites)")
    for league in LEAGUES:
        subset = [row for row in counted if row["league"] == league]
        if not subset:
            continue
        pct, half = rate([row["home_won"] for row in subset])
        swapped = sum(1 for row in subset if row["away_is_away"] == "0")
        first = min(row["game_start_utc"] for row in subset)[:10]
        last = max(row["game_start_utc"] for row in subset)[:10]
        print(f"{league:5} games {len(subset):5d}  home_win {pct:5.1f}% +/- {half:4.2f}  first_named_was_home {swapped:4d}  {first} to {last}")

    print("\n== By calendar year, 100 or more games")
    by_year = defaultdict(list)
    for row in counted:
        by_year[(row["league"], row["game_start_utc"][:4])].append(row["home_won"])
    for (league, year), values in sorted(by_year.items()):
        if len(values) >= 100:
            pct, half = rate(values)
            print(f"{league:5} {year}  games {len(values):5d}  home_win {pct:5.1f}% +/- {half:4.2f}")

    print("\n== The study's first reading (second outcome = home) on the same counted games, for comparison")
    for league in LEAGUES:
        subset = [row for row in counted if row["league"] == league]
        if subset:
            pct, _ = rate([int(row["winning_outcome"] == "1") for row in subset])
            print(f"{league:5} second_outcome_won {pct:5.1f}%")

    with open(output_path, "w", newline="") as handle:
        fields = ["condition_id", "event_slug", "league", "espn_id", "game_start_utc", "season_type", "away_is_away", "home_team", "home_outcome_index", "home_won"]
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(counted)
    print(f"\nwrote {output_path} ({len(counted)} games)")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
