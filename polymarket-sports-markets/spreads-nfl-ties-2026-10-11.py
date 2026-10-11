"""Every tied NFL regular-season and postseason game from ESPN's public scoreboard, September 2024 to the 2026 opener
(#23724, epic #23652).

The NFL margins chart on /research/point-spreads-polymarket counted 570 games from
football-scoreboard.csv, the ESPN match of the football underdogs study. That study keeps only
moneylines that settled to one team ("a tie or cancellation settles 50-50 and is left out",
football-upsets.sql), so a tied game could not reach the margins count. This script lists the
ties the count missed. It reads ESPN's scoreboard one week at a time (a date-range query answers 400): regular-season
weeks 1 to 18 and postseason weeks 1 to 5 of the 2024 and 2025 seasons, and 2026 regular-season week 1, and keeps games
whose ESPN start falls from 2024-09-05 to 2026-09-11 (the window the margins count covers) with status final.

For each tie it then reads the game's Polymarket event from the public Gamma API (slug nfl-<away>-<home>-<US date>, as
Polymarket names NFL games) and prints how its moneyline and spreads settled. It writes the ties to
spreads-nfl-ties-2026-10-11.csv, which spreads-nfl-margins-2026-10-11.py adds to its count.

Usage: python3 spreads-nfl-ties-2026-10-11.py
"""

import csv
from datetime import datetime, timedelta, timezone

import json
import sys
import time
import urllib.request

GAMMA = "https://gamma-api.polymarket.com/events?slug={slug}"
URL = "https://site.api.espn.com/apis/site/v2/sports/football/nfl/scoreboard?dates={season}&seasontype={kind}&week={week}&limit=300"
FIRST, LAST = "2024-09-05", "2026-09-11"
NAMES = {2: "regular season", 3: "postseason"}


def fetch_json(url, headers=None):
    # As in football-scoreboard.py, ESPN answers Python's default user agent; Gamma answers 403 to it
    # and 200 to a named one, as in the 0xinsider repository's docs/research-articles/verification/2026-10-11-league-guides-charts.py.
    for attempt in range(5):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=headers or {}), timeout=30) as response:
                return json.load(response)
        except Exception as error:  # a transient network error is retried, the fifth failure raises
            if attempt == 4:
                raise
            print(f"retry {url}: {error}", file=sys.stderr)
            time.sleep(2 * (attempt + 1))
    raise RuntimeError("unreachable")


pages = [(2024, 2, week) for week in range(1, 19)] + [(2024, 3, week) for week in range(1, 6)]
pages += [(2025, 2, week) for week in range(1, 19)] + [(2025, 3, week) for week in range(1, 6)]
pages += [(2026, 2, 1)]

seen = set()
finals = {2: 0, 3: 0}
ties = []
for season, kind, week in pages:
    for event in fetch_json(URL.format(season=season, kind=kind, week=week)).get("events", []):
        start = event["date"][:10]
        if event["id"] in seen or not FIRST <= start <= LAST:
            continue
        seen.add(event["id"])
        competition = event["competitions"][0]
        if not competition["status"]["type"]["completed"]:
            continue
        finals[kind] += 1
        scores = {team["team"]["abbreviation"]: int(team["score"]) for team in competition["competitors"]}
        if len(set(scores.values())) == 1:
            away = next(t for t in competition["competitors"] if t["homeAway"] == "away")["team"]
            home = next(t for t in competition["competitors"] if t["homeAway"] == "home")["team"]
            ties.append({"espn_id": event["id"], "espn_start_utc": event["date"], "season_type": kind,
                         "away": away["displayName"], "home": home["displayName"], "away_abbr": away["abbreviation"],
                         "home_abbr": home["abbreviation"], "score": list(scores.values())[0],
                         "detail": competition["status"]["type"]["detail"]})

print(f"== ESPN NFL games completed from {FIRST} to {LAST} (ESPN start, UTC)")
print(f"regular season {finals[2]}, postseason {finals[3]}, total {finals[2] + finals[3]}")
print(f"== ties: {len(ties)}")
for tie in ties:
    print(f"{tie['espn_start_utc']} espn_id {tie['espn_id']} {NAMES[tie['season_type']]}: {tie['away']} {tie['score']} "
          f"at {tie['home']} {tie['score']} ({tie['detail']})")
    # Polymarket dates an NFL game by its US Eastern day; Eastern is UTC-4 for every game from September to early
    # November, which covers each tie this window holds.
    day = (datetime.fromisoformat(tie["espn_start_utc"].replace("Z", "+00:00")) - timedelta(hours=4)).date()
    tie["polymarket_slug"] = f"nfl-{tie['away_abbr'].lower()}-{tie['home_abbr'].lower()}-{day}"
    events = fetch_json(GAMMA.format(slug=tie["polymarket_slug"]), {"User-Agent": "0xinsider-research"})
    print(f"  Polymarket {tie['polymarket_slug']}: {len(events)} event(s), read {datetime.now(timezone.utc):%Y-%m-%dT%H:%M:%SZ}")
    tie["moneyline_settled"] = ""
    for event in events:
        for market in event.get("markets", []):
            if market.get("sportsMarketType") not in ("moneyline", "spreads"):
                continue
            prices = json.loads(market["outcomePrices"])
            outcomes = json.loads(market["outcomes"])
            print(f"  {market['sportsMarketType']:9} {market['question']}: {outcomes[0]} {prices[0]}, {outcomes[1]} "
                  f"{prices[1]}, closed {market['closed']}, reported volume {float(market['volumeNum']):,.0f} shares")
            if market.get("sportsMarketType") == "moneyline":
                tie["moneyline_settled"] = "/".join(prices)

with open("spreads-nfl-ties-2026-10-11.csv", "w", newline="") as handle:
    fields = ["espn_id", "espn_start_utc", "season_type", "away", "home", "score", "polymarket_slug", "moneyline_settled"]
    writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore", lineterminator="\n")
    writer.writeheader()
    writer.writerows(ties)
