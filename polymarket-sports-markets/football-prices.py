"""Kickoff prices for every settled Polymarket NFL and college football moneyline, from the public CLOB price history.

Input: football-games.csv (the read-only export) and football-scoreboard.csv
(the ESPN game each market settled on). The cutoff is the earlier of the market's scheduled start and ESPN's listed
start, or the market's start when ESPN has no match: a price read after kickoff already carries part of the game.
For each game it reads
GET https://clob.polymarket.com/prices-history?market=<token>&startTs=<cutoff - 24h>&endTs=<cutoff>&fidelity=1
for the away team's token, and keeps:
  kickoff_price      the last history point at or before the cutoff (the away team's price; the home team's is 1 minus it)
  minutes_before     how many minutes before the cutoff that point is
  day_before_price   the first point in the 24 hours before the cutoff (the earliest price in the window)
  points             how many points the window returned
A game whose window returns no point is written with empty prices and counted in the summary.
For a fixed sample of 100 games it also reads the home token and reports how far the two kickoff prices sum from 1.

Output: football-prices.csv and a summary on stdout.
Usage: python3 football-prices.py football-games.csv football-scoreboard.csv football-prices.csv
"""

import csv
import json
import random
import sys
import threading
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone

HISTORY = "https://clob.polymarket.com/prices-history?market={token}&startTs={start}&endTs={end}&fidelity=1"
WINDOW_SECONDS = 24 * 3600
SAMPLE_SEED = 20260913
pace = threading.Semaphore(4)


def fetch_history(token, start, end):
    request = urllib.request.Request(HISTORY.format(token=token, start=start, end=end), headers={"User-Agent": "Mozilla/5.0 (0xinsider research)"})
    for attempt in range(6):
        try:
            with pace:
                with urllib.request.urlopen(request, timeout=30) as response:
                    payload = json.load(response)
                time.sleep(0.35)
            return payload.get("history", [])
        except Exception as error:  # a transient network or rate-limit error is retried, the sixth failure raises
            if attempt == 5:
                raise
            print(f"retry {token[:12]}: {error}", file=sys.stderr)
            time.sleep(3 * (attempt + 1))
    raise RuntimeError("unreachable")


def last_before(history, start):
    before = [point for point in history if point["t"] <= start]
    if not before:
        return None, None, None
    last = max(before, key=lambda point: point["t"])
    first = min(before, key=lambda point: point["t"])
    return last["p"], round((start - last["t"]) / 60, 1), first["p"]


def utc_seconds(text):
    return int(datetime.strptime(text, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).timestamp())


def espn_seconds(text):
    # ESPN writes starts without seconds ("2025-09-07T17:00Z").
    return int(datetime.strptime(text, "%Y-%m-%dT%H:%MZ").replace(tzinfo=timezone.utc).timestamp())


def main(markets_path, linescores_path, output_path):
    markets = list(csv.DictReader(open(markets_path)))
    espn_start = {row["condition_id"]: row["espn_start_utc"] for row in csv.DictReader(open(linescores_path))}
    sample_ids = set(market["condition_id"] for market in random.Random(SAMPLE_SEED).sample(markets, 100))

    def work(market):
        start = utc_seconds(market["game_start_utc"])
        if espn_start[market["condition_id"]]:
            start = min(start, espn_seconds(espn_start[market["condition_id"]]))
        history = fetch_history(market["away_token"], start - WINDOW_SECONDS, start)
        price, minutes_before, day_before = last_before(history, start)
        row = {
            "condition_id": market["condition_id"],
            "event_slug": market["event_slug"],
            "game_start_utc": market["game_start_utc"],
            "cutoff_utc": datetime.fromtimestamp(start, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "away_token": market["away_token"],
            "kickoff_price": "" if price is None else price,
            "minutes_before": "" if minutes_before is None else minutes_before,
            "day_before_price": "" if day_before is None else day_before,
            "points": len(history),
            "home_token_kickoff_price": "",
        }
        if market["condition_id"] in sample_ids:
            other, _, _ = last_before(fetch_history(market["home_token"], start - WINDOW_SECONDS, start), start)
            row["home_token_kickoff_price"] = "" if other is None else other
        return row

    with ThreadPoolExecutor(max_workers=4) as pool:
        rows = list(pool.map(work, markets))

    with open(output_path, "w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)

    priced = [row for row in rows if row["kickoff_price"] != ""]
    gaps = sorted(row["minutes_before"] for row in priced)
    print(f"run_at {datetime.now(timezone.utc).isoformat(timespec='seconds')}")
    print(f"games {len(rows)}  cutoff_moved_earlier_to_espn_listed_start {sum(1 for row in rows if row['cutoff_utc'] != row['game_start_utc'])}")
    print(f"with_a_price_at_or_before_the_cutoff {len(priced)}  without {len(rows) - len(priced)}")
    if gaps:
        print(f"minutes_before_cutoff: median {gaps[len(gaps) // 2]}  p90 {gaps[int(len(gaps) * 0.9)]}  max {gaps[-1]}  over_60 {sum(1 for gap in gaps if gap > 60)}")
    pairs = [row for row in rows if row["home_token_kickoff_price"] != "" and row["kickoff_price"] != ""]
    if pairs:
        sums = sorted(float(row["kickoff_price"]) + float(row["home_token_kickoff_price"]) for row in pairs)
        print(f"complement_sample {len(pairs)}: sum min {sums[0]:.4f}  median {sums[len(sums) // 2]:.4f}  max {sums[-1]:.4f}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3])
