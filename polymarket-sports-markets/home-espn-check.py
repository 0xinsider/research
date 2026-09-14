"""Check the home team of every game in the home advantage study against ESPN's scoreboard.

Input: a CSV of settled US league moneylines (columns condition_id, event_slug, league, away, home,
game_start_utc, winning_outcome), where `away` is the first outcome and `home` the second, the reading the
study used. For each game date (US Eastern, plus or minus a day) it reads ESPN's public scoreboard for the league
(site.api.espn.com/apis/site/v2/sports/{sport}/{league}/scoreboard; college football for the FBS and FCS groups),
matches the game whose two teams carry the Polymarket names and whose listed start is nearest the market's, and
records:
  espn_start_utc   ESPN's listed start for the matched game
  season_type      1 preseason, 2 regular season, 3 postseason
  neutral_site     1 when ESPN marks the game at a neutral site
  away_score, home_score, winner_agrees (the market's settlement names the team with more points)
  away_is_away     1 when ESPN lists the Polymarket away team as the away team
A game with no final ESPN match is written with empty fields and counted. Responses are cached under
espn-scoreboard-cache/ so a re-run reads the same data.

Usage: python3 home-espn-check.py home-advantage-games.csv home-espn-check.csv
"""

import csv
import json
import os
import re
import sys
import unicodedata
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

EASTERN = ZoneInfo("America/New_York")
BASE = "https://site.api.espn.com/apis/site/v2/sports"
# ESPN pages a scoreboard at 25 events unless `limit` is set; a limit of 900 was ignored on 2026-09-14 and 300 was not.
URLS = {
    "nfl": [BASE + "/football/nfl/scoreboard?dates={date}&limit=300"],
    "cfb": [
        BASE + "/football/college-football/scoreboard?dates={date}&groups=80&limit=300",
        BASE + "/football/college-football/scoreboard?dates={date}&groups=81&limit=300",
    ],
    "nba": [BASE + "/basketball/nba/scoreboard?dates={date}&limit=300"],
    "wnba": [BASE + "/basketball/wnba/scoreboard?dates={date}&limit=300"],
    "nhl": [BASE + "/hockey/nhl/scoreboard?dates={date}&limit=300"],
    "mlb": [BASE + "/baseball/mlb/scoreboard?dates={date}&limit=300"],
}
CACHE = "espn-scoreboard-cache"


def fetch_json(url):
    # ESPN's edge answered 403 to a browser user agent and to a custom one on 2026-09-14, and 200 to
    # Python's default user agent, so the request sends no User-Agent header of its own.
    request = urllib.request.Request(url)
    for attempt in range(5):
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.load(response)
        except Exception as error:  # a transient network error is retried, the fifth failure raises
            if attempt == 4:
                raise
            print(f"retry {url}: {error}", file=sys.stderr)
            time.sleep(2 * (attempt + 1))
    raise RuntimeError("unreachable")


def parse_utc(text):
    for layout in ("%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%dT%H:%MZ"):
        try:
            return datetime.strptime(text, layout).replace(tzinfo=timezone.utc)
        except ValueError:
            continue
    raise ValueError(text)


def norm(text):
    # "San José State" and "Hawai'i" on ESPN read as "san jose state" and "hawaii", like Polymarket's spelling.
    plain = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode().lower()
    plain = plain.replace("'", "").replace("&", " and ").replace("st.", "state")
    return re.sub(r"[^a-z0-9]+", " ", plain).strip()


# Polymarket team names that ESPN spells another way, checked against ESPN's team lists on 2026-09-14.
ALIASES = {
    "appalachian state": "app state",
    "bowling": "bowling green",
    "north carolina state": "nc state",
    "unlv runnin": "unlv",
    "southeastern louisiana": "se louisiana",
    "nicholls state": "nicholls",
    "tennessee martin": "ut martin",
    "university at albany": "ualbany",
    "southern university": "southern",
    "grambling state": "grambling",
    "southern mississippi": "southern miss",
    "central connecticut state": "central connecticut",
    "miami fl": "miami",
    "louisiana monroe": "ul monroe",
    "portlandfire": "portland fire",
}


def polymarket_name(text):
    name = norm(text)
    return ALIASES.get(name, name)


def names(team):
    fields = [team.get("displayName"), team.get("shortDisplayName"), team.get("name"), team.get("location"), team.get("abbreviation")]
    if team.get("location") and team.get("name"):
        fields.append(f"{team['location']} {team['name']}")
    return {norm(field) for field in fields if field}


def cache_path(league, url_index, date):
    return os.path.join(CACHE, f"{league}-{url_index}-{date}.json")


def load(league, date):
    events = []
    for index, template in enumerate(URLS[league]):
        path = cache_path(league, index, date)
        if not os.path.exists(path):
            payload = fetch_json(template.format(date=date.replace("-", "")))
            with open(path + ".part", "w") as handle:
                json.dump(payload, handle)
            os.replace(path + ".part", path)
        # One FCS page on 2025-10-18 carried an empty event object; only complete events are kept.
        events.extend(event for event in json.load(open(path)).get("events", []) if event.get("id") and event.get("competitions"))
    return events


def main(games_path, output_path):
    os.makedirs(CACHE, exist_ok=True)
    games = list(csv.DictReader(open(games_path)))
    needed = sorted({
        (game["league"], (parse_utc(game["game_start_utc"]).astimezone(EASTERN).date() + timedelta(days=offset)).isoformat())
        for game in games
        for offset in (-1, 0, 1)
    })

    def prefetch(item):
        league, date = item
        load(league, date)
        time.sleep(0.1)

    with ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(prefetch, needed))

    rows = []
    for game in games:
        start = parse_utc(game["game_start_utc"])
        day = start.astimezone(EASTERN).date()
        away_name, home_name = polymarket_name(game["away"]), polymarket_name(game["home"])
        candidates = []
        seen = set()
        for offset in (0, -1, 1):
            for event in load(game["league"], (day + timedelta(days=offset)).isoformat()):
                if event["id"] in seen:
                    continue
                seen.add(event["id"])
                competition = event["competitions"][0]
                teams = {team["homeAway"]: team for team in competition["competitors"]}
                if "home" not in teams or "away" not in teams:
                    continue
                espn_home, espn_away = names(teams["home"]["team"]), names(teams["away"]["team"])
                if away_name in espn_away and home_name in espn_home:
                    away_is_away = 1
                elif away_name in espn_home and home_name in espn_away:
                    away_is_away = 0
                else:
                    continue
                gap = abs((parse_utc(event["date"]) - start).total_seconds()) / 3600
                candidates.append((gap, event, competition, teams, away_is_away))
        candidates.sort(key=lambda item: item[0])
        row = {key: game[key] for key in ("condition_id", "event_slug", "league", "away", "home", "game_start_utc", "winning_outcome")}
        final = [item for item in candidates if item[1]["status"]["type"].get("completed") and item[0] <= 48]
        # How many completed games between the same two teams the three-day window holds: one means the match
        # cannot be a neighbouring game of the same series.
        row["final_candidates"] = len(final)
        if not final:
            row.update({"espn_id": "", "espn_start_utc": "", "hours_from_start": "", "season_type": "", "neutral_site": "",
                        "away_score": "", "home_score": "", "away_is_away": "", "winner_agrees": ""})
        else:
            gap, event, competition, teams, away_is_away = final[0]
            polymarket_away = teams["away"] if away_is_away else teams["home"]
            polymarket_home = teams["home"] if away_is_away else teams["away"]
            away_score, home_score = int(polymarket_away.get("score") or 0), int(polymarket_home.get("score") or 0)
            market_winner_is_away = game["winning_outcome"] == "0"
            row.update({
                "espn_id": event["id"],
                "espn_start_utc": event["date"],
                "hours_from_start": round(gap, 2),
                "season_type": event.get("season", {}).get("type", ""),
                "neutral_site": int(bool(competition.get("neutralSite"))),
                "away_score": away_score,
                "home_score": home_score,
                "away_is_away": away_is_away,
                "winner_agrees": int((away_score > home_score) == market_winner_is_away and away_score != home_score),
            })
        rows.append(row)

    with open(output_path, "w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)

    print(f"run_at {datetime.now(timezone.utc).isoformat(timespec='seconds')}")
    for league in ("nba", "nhl", "mlb", "wnba", "nfl", "cfb"):
        subset = [row for row in rows if row["league"] == league]
        matched = [row for row in subset if row["espn_id"] != ""]
        ids = {}
        for row in matched:
            ids[row["espn_id"]] = ids.get(row["espn_id"], 0) + 1
        print(
            f"{league}: games {len(subset)}  matched {len(matched)}  unmatched {len(subset) - len(matched)}  "
            f"winner_agrees {sum(row['winner_agrees'] for row in matched)}  disagrees {sum(1 for row in matched if row['winner_agrees'] == 0)}  "
            f"away_listed_away {sum(row['away_is_away'] for row in matched)}  "
            f"espn_games_matched_twice {sum(1 for count in ids.values() if count > 1)}  "
            f"season_types {sorted({str(row['season_type']) for row in matched})}  neutral {sum(row['neutral_site'] for row in matched)}  "
            f"polymarket_start_later_than_espn {sum(1 for row in matched if parse_utc(row['espn_start_utc']) < parse_utc(row['game_start_utc']))}"
        )
        for row in [row for row in matched if row["winner_agrees"] == 0][:10]:
            print("  disagree", row["event_slug"], row["away"], row["home"], row["winning_outcome"], row["away_score"], row["home_score"])
        for row in [row for row in subset if row["espn_id"] == ""][:15]:
            print("  unmatched", row["event_slug"], "|", row["away"], "|", row["home"])


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
