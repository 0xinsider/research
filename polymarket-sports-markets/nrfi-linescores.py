"""Cross-check every settled Polymarket NRFI market against MLB's official linescore.

Input: nrfi-markets.csv (the read-only export of settled NRFI markets; columns condition_id,
event_slug, matchup, fmt, token_id_yes, token_id_no, game_start_utc, winning_outcome).
For each game date (US Eastern) it reads the public MLB Stats API schedule with linescores,
matches each market to the game between the same two teams whose listed start is nearest the
market's scheduled start. A postponed game keeps its gamePk when MLB makes it up, so when that game
is not final the script follows the same gamePk up to seven days later. It then compares first-inning
runs with the market's settlement. It also records which team MLB lists at home,
checking that the matchup names the away team first, and the runs each team scored in its half of the
first inning. Schedule responses are cached under mlb-schedule-cache/ so a re-run reads the same data.

Output: nrfi-linescores.csv (one row per market, with MLB's listed start for the game that was played)
and a summary on stdout.
Usage: python3 nrfi-linescores.py nrfi-markets.csv nrfi-linescores.csv
"""

import csv
import json
import os
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

EASTERN = ZoneInfo("America/New_York")
SCHEDULE = "https://statsapi.mlb.com/api/v1/schedule?sportId=1&date={date}&hydrate=linescore,team"


def fetch_json(url):
    request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (0xinsider research)"})
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


def team_names(team):
    names = {team.get("name"), team.get("teamName"), team.get("clubName"), team.get("shortName"), team.get("franchiseName")}
    return {name.strip().lower() for name in names if name}


def completed(game):
    """A game played to its end on this listing: final, with innings, and not a postponed, suspended or canceled entry."""
    status = game.get("status", {})
    detailed = status.get("detailedState", "")
    innings = (game.get("linescore") or {}).get("innings") or []
    return status.get("abstractGameState") == "Final" and bool(innings) and not detailed.startswith(("Postponed", "Suspended", "Cancelled"))


def parse_utc(text):
    return datetime.strptime(text, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)


def main(markets_path, output_path):
    markets = list(csv.DictReader(open(markets_path)))
    markets_by_id = {market["condition_id"]: market for market in markets}
    schedules = {}

    os.makedirs("mlb-schedule-cache", exist_ok=True)

    def games_on(date):
        if date not in schedules:
            cache_path = os.path.join("mlb-schedule-cache", f"{date}.json")
            if os.path.exists(cache_path):
                payload = json.load(open(cache_path))
            else:
                payload = fetch_json(SCHEDULE.format(date=date))
                with open(cache_path, "w") as handle:
                    json.dump(payload, handle)
                time.sleep(0.2)
            schedules[date] = [game for day in payload.get("dates", []) for game in day.get("games", [])]
        return schedules[date]

    needed = sorted({
        (parse_utc(market["game_start_utc"]).astimezone(EASTERN).date() + timedelta(days=offset)).isoformat()
        for market in markets
        for offset in range(-1, 8)
    })

    def prefetch(date):
        cache_path = os.path.join("mlb-schedule-cache", f"{date}.json")
        if not os.path.exists(cache_path):
            payload = fetch_json(SCHEDULE.format(date=date))
            with open(cache_path + ".part", "w") as handle:
                json.dump(payload, handle)
            os.replace(cache_path + ".part", cache_path)

    with ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(prefetch, needed))

    rows = []
    for market in markets:
        start = parse_utc(market["game_start_utc"])
        first, second = [part.strip().lower() for part in market["matchup"].split(" vs. ", 1)]
        local_day = start.astimezone(EASTERN).date()
        listed = []
        for offset in (0, -1, 1):
            for game in games_on((local_day + timedelta(days=offset)).isoformat()):
                away, home = game["teams"]["away"]["team"], game["teams"]["home"]["team"]
                away_names, home_names = team_names(away), team_names(home)
                if first in away_names | home_names and second in away_names | home_names:
                    gap = abs((parse_utc(game["gameDate"]) - start).total_seconds()) / 3600
                    listed.append((gap, game, first in away_names))
        listed.sort(key=lambda item: item[0])
        candidates = []
        followed = 0
        if listed:
            gap, game, first_is_away = listed[0]
            if not completed(game):
                later = [
                    candidate
                    for offset in range(1, 8)
                    for candidate in games_on((local_day + timedelta(days=offset)).isoformat())
                    if candidate["gamePk"] == game["gamePk"] and completed(candidate)
                ]
                if later:
                    game = later[0]
                    gap = abs((parse_utc(game["gameDate"]) - start).total_seconds()) / 3600
                    followed = 1
            if completed(game):
                candidates.append((gap, game, first_is_away))
        row = {
            "condition_id": market["condition_id"],
            "event_slug": market["event_slug"],
            "matchup": market["matchup"],
            "fmt": market["fmt"],
            "winning_outcome": market["winning_outcome"],
        }
        yes_won = market["winning_outcome"] == "0"
        market_no_run = yes_won if market["fmt"] == "yes_is_no_run" else not yes_won
        row["market_no_run"] = int(market_no_run)
        row["followed_postponement"] = followed
        if not candidates:
            row.update({"mlb_game_pk": "", "mlb_game_start_utc": "", "hours_from_start": "", "away_runs_first": "", "home_runs_first": "", "first_inning_runs": "", "mlb_no_run": "", "agrees": "", "first_named_is_away": "", "home_team": "", "away_team": ""})
        else:
            gap, game, first_is_away = candidates[0]
            first_inning = game["linescore"]["innings"][0]
            away_runs = first_inning.get("away", {}).get("runs") or 0
            home_runs = first_inning.get("home", {}).get("runs") or 0
            runs = away_runs + home_runs
            row.update({
                "mlb_game_pk": game["gamePk"],
                "mlb_game_start_utc": game["gameDate"],
                "hours_from_start": round(gap, 2),
                "away_runs_first": away_runs,
                "home_runs_first": home_runs,
                "first_inning_runs": runs,
                "mlb_no_run": int(runs == 0),
                "agrees": int((runs == 0) == market_no_run),
                "first_named_is_away": int(first_is_away),
                "home_team": game["teams"]["home"]["team"]["name"],
                "away_team": game["teams"]["away"]["team"]["name"],
            })
        rows.append(row)

    with open(output_path, "w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)

    matched = [row for row in rows if row["mlb_game_pk"] != ""]
    print(f"run_at {datetime.now(timezone.utc).isoformat(timespec='seconds')}")
    print(f"markets {len(rows)}  matched_to_a_final_mlb_game {len(matched)}  unmatched {len(rows) - len(matched)}")
    print(f"settlement_agrees_with_linescore {sum(row['agrees'] for row in matched)}  disagrees {sum(1 for row in matched if row['agrees'] == 0)}")
    print(f"first_named_team_is_away {sum(row['first_named_is_away'] for row in matched)}  first_named_team_is_home {sum(1 for row in matched if row['first_named_is_away'] == 0)}")
    game_counts = {}
    for row in matched:
        game_counts[row["mlb_game_pk"]] = game_counts.get(row["mlb_game_pk"], 0) + 1
    print(f"distinct_mlb_games {len(game_counts)}  games_matched_by_two_or_more_markets {sum(1 for count in game_counts.values() if count > 1)}")
    print(f"postponed_games_followed_to_their_makeup {sum(row['followed_postponement'] for row in rows)}")
    listed_later = [row for row in matched if parse_utc(row["mlb_game_start_utc"]) < parse_utc(markets_by_id[row["condition_id"]]["game_start_utc"])]
    print(f"polymarket_start_later_than_mlb_listed_start {len(listed_later)}")
    over_six = [row for row in matched if row["hours_from_start"] > 6]
    print(f"matched_game_started_more_than_6h_from_the_listed_start {len(over_six)}")
    for fmt in ("yes_is_no_run", "yes_is_run"):
        subset = [row for row in matched if row["fmt"] == fmt]
        print(f"format {fmt}: matched {len(subset)}, agree {sum(row['agrees'] for row in subset)}")
    for row in [row for row in matched if row["agrees"] == 0][:20]:
        print("disagree", row["event_slug"], row["matchup"], row["fmt"], row["winning_outcome"], row["first_inning_runs"], row["hours_from_start"])
    for row in [row for row in matched if row["hours_from_start"] > 6 or game_counts[row["mlb_game_pk"]] > 1]:
        print("check", row["event_slug"], row["matchup"], row["mlb_game_pk"], row["hours_from_start"], row["followed_postponement"], row["first_inning_runs"], row["market_no_run"])
    for row in [row for row in rows if row["mlb_game_pk"] == ""][:20]:
        print("unmatched", row["event_slug"], row["matchup"])


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
