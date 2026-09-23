#!/usr/bin/env python3
"""#14900. The final result of each game in the #14883 three-venue capture.

Reads ESPN's scoreboard -- the same source, the same endpoint and the same day
window the capture used -- and writes one row per captured game with the final
score. The scoring script reads that CSV, so every figure on the page can be
re-derived without a network call.

The sample is fixed by the capture. This script takes the 81 rows of
games.csv, looks each one up by the ESPN event id the
capture already recorded in capture.json, and fails if a
game is missing or not final. Nothing is added, nothing is dropped, and no game
is matched by name at this stage: the id was written before any result existed.

Usage, from this directory:
  python3 results.py --games games.csv --capture capture.json --out results.csv
"""

import argparse
import csv
import json
import sys
import time
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

# The capture's own league configuration, copied from
# capture.py so this script reads the identical paths.
LEAGUES = {
    "nfl": {"espn": "football/nfl", "espn_extra": {}},
    "cfb": {
        "espn": "football/college-football",
        # groups=80 is every FBS game; the default scoreboard is the top 25 only.
        "espn_extra": {"groups": "80", "limit": "400"},
    },
    "mlb": {"espn": "baseball/mlb", "espn_extra": {}},
    "wnba": {"espn": "basketball/wnba", "espn_extra": {}},
}

# The capture's window, plus two days, because a scoreboard files a game under
# its local date and the last kickoff was 2026-09-22T00:15Z.
DAYS_FROM = "20260918"
DAYS_TO = "20260923"


def get_json(url: str):
    # ESPN's edge answers 403 to any user agent it does not recognise and 200 to
    # Python's default, so these reads send no User-Agent of their own. Same as
    # the capture.
    request = urllib.request.Request(url, headers={"Accept": "application/json"})
    last_error = None
    for attempt in range(4):
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.loads(response.read().decode("utf-8"))
        except Exception as error:  # noqa: BLE001 - retried, then raised below
            last_error = error
            time.sleep(1.5 * (attempt + 1))
    raise RuntimeError(f"GET {url} failed after 4 attempts: {last_error}")


def espn_days(date_from: str, date_to: str) -> list[str]:
    day = datetime.strptime(date_from, "%Y%m%d")
    last = datetime.strptime(date_to, "%Y%m%d")
    days = []
    while day <= last:
        days.append(day.strftime("%Y%m%d"))
        day += timedelta(days=1)
    return days


def scoreboard(league: str) -> dict[str, dict]:
    """Every event ESPN files for this league in the window, keyed by event id."""
    config = LEAGUES[league]
    events: dict[str, dict] = {}
    for day in espn_days(DAYS_FROM, DAYS_TO):
        params = {"dates": day, **config["espn_extra"]}
        url = (
            f"https://site.api.espn.com/apis/site/v2/sports/{config['espn']}"
            f"/scoreboard?{urllib.parse.urlencode(params)}"
        )
        for event in get_json(url).get("events", []):
            event_id = event.get("id")
            if event_id and event_id not in events:
                events[event_id] = event
    return events


def captured_event_ids(capture_path: str) -> dict[tuple[str, str], str]:
    """(league, ESPN event name) -> ESPN event id, as recorded at capture time."""
    capture = json.load(open(capture_path, encoding="utf-8"))
    ids: dict[tuple[str, str], str] = {}
    for league, venues in capture["leagues"].items():
        for game in venues["draftkings_via_espn"]["games"]:
            ids[(league, game["name"])] = game["id"]
    return ids


def final_score(event: dict) -> tuple[str, int, int]:
    competition = (event.get("competitions") or [{}])[0]
    status = ((competition.get("status") or {}).get("type") or {}).get("name") or ""
    home = away = None
    for competitor in competition.get("competitors", []):
        score = competitor.get("score")
        if competitor.get("homeAway") == "home":
            home = score
        elif competitor.get("homeAway") == "away":
            away = score
    if home is None or away is None:
        raise RuntimeError(f"event {event.get('id')} has no two-sided score")
    return status, int(home), int(away)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--games", required=True, help="the committed 81-game capture CSV")
    parser.add_argument("--capture", required=True, help="the committed capture JSON")
    parser.add_argument("--out", required=True, help="results CSV to write")
    args = parser.parse_args()

    games = list(csv.DictReader(open(args.games, encoding="utf-8")))
    ids = captured_event_ids(args.capture)
    boards = {league: scoreboard(league) for league in sorted({row["league"] for row in games})}

    read_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    rows = []
    problems = []
    for row in games:
        league = row["league"]
        event_id = ids.get((league, row["game"]))
        if not event_id:
            problems.append(f"{league} {row['game']}: no ESPN id in the capture")
            continue
        event = boards[league].get(event_id)
        if not event:
            problems.append(f"{league} {row['game']} (id {event_id}): not on the scoreboard")
            continue
        status, home_score, away_score = final_score(event)
        if status != "STATUS_FINAL":
            problems.append(f"{league} {row['game']} (id {event_id}): status {status}")
            continue
        rows.append(
            {
                "read_at": read_at,
                "league": league,
                "game": row["game"],
                "start_utc": row["start_utc"],
                "espn_event_id": event_id,
                "status": status,
                "home_score": home_score,
                "away_score": away_score,
                # 1 home win, 0 away win, 0.5 tie. American football can tie;
                # the scoring script decides what a tie does, not this reader.
                "home_result": "1" if home_score > away_score else ("0" if home_score < away_score else "0.5"),
            }
        )

    if problems:
        for problem in problems:
            print(f"UNRESOLVED {problem}", file=sys.stderr)
        raise SystemExit(
            f"{len(problems)} of {len(games)} captured games are not final; "
            "the sample is fixed, so nothing is written"
        )

    with open(args.out, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        for row in sorted(rows, key=lambda r: (r["league"], r["start_utc"], r["game"])):
            writer.writerow(row)

    print(f"read ESPN at {read_at}")
    print(f"wrote {args.out}: {len(rows)} of {len(games)} captured games, all final")
    home_wins = sum(1 for row in rows if row["home_result"] == "1")
    ties = sum(1 for row in rows if row["home_result"] == "0.5")
    print(f"home wins {home_wins}, away wins {len(rows) - home_wins - ties}, ties {ties}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
