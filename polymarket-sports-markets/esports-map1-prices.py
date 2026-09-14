"""Starting prices for every counted Polymarket esports BO3 series moneyline, from the public CLOB price history.

Input: esports-map1-series.csv (the read-only export, 9,504 series across CS2, Valorant,
Dota 2 and LoL). The cutoff is the series moneyline's own `game_start_time` (Polymarket's listed match start).
For each series it reads
  GET https://clob.polymarket.com/prices-history?market=<token>&startTs=<cutoff - 24h>&endTs=<cutoff>&fidelity=1
for team0's token (`token_id_yes`) and keeps:
  start_price      the last history point at or before the cutoff (team0's price; team1's is 1 minus it)
  minutes_before   how many minutes before the cutoff that point is
  points           how many points the window returned
A series whose window returns no point is written with an empty price and counted in the summary. For a fixed
100-series sample it also reads team1's token (token_id_no) and reports how far the two prices sum from 1.

Output: esports-map1-prices.csv and a summary on stdout.
Usage: python3 esports-map1-prices.py esports-map1-series.csv esports-map1-prices.csv
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
SAMPLE_SEED = 20260914
pace = threading.Semaphore(6)


def fetch_history(token, start, end):
    request = urllib.request.Request(
        HISTORY.format(token=token, start=start, end=end),
        headers={"User-Agent": "Mozilla/5.0 (0xinsider research)"},
    )
    for attempt in range(6):
        try:
            with pace:
                with urllib.request.urlopen(request, timeout=30) as response:
                    payload = json.load(response)
                time.sleep(0.25)
            return payload.get("history", [])
        except Exception as error:
            if attempt == 5:
                raise
            print(f"retry {token[:12]}: {error}", file=sys.stderr)
            time.sleep(3 * (attempt + 1))
    raise RuntimeError("unreachable")


def last_before(history, start):
    before = [point for point in history if point["t"] <= start]
    if not before:
        return None, None
    last = max(before, key=lambda point: point["t"])
    return last["p"], round((start - last["t"]) / 60, 1)


def utc_seconds(text):
    return int(datetime.strptime(text, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).timestamp())


def main(series_path, output_path):
    rows = list(csv.DictReader(open(series_path)))
    sample_ids = set(row["condition_id"] for row in random.Random(SAMPLE_SEED).sample(rows, min(100, len(rows))))

    def work(row):
        start = utc_seconds(row["game_start_utc"])
        history = fetch_history(row["token_id_yes"], start - WINDOW_SECONDS, start)
        price, minutes_before = last_before(history, start)
        out = dict(row)
        out["start_price"] = "" if price is None else price
        out["minutes_before"] = "" if minutes_before is None else minutes_before
        out["points"] = len(history)
        if row["condition_id"] in sample_ids:
            home_history = fetch_history(row["token_id_no"], start - WINDOW_SECONDS, start)
            home_price, _ = last_before(home_history, start)
            out["complement_sum"] = "" if price is None or home_price is None else round(price + home_price, 4)
        else:
            out["complement_sum"] = ""
        return out

    with ThreadPoolExecutor(max_workers=6) as pool:
        results = list(pool.map(work, rows))

    fieldnames = list(results[0].keys())
    with open(output_path, "w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(results)

    priced = [r for r in results if r["start_price"] != ""]
    print(f"series {len(results)}  priced {len(priced)}  no_price {len(results) - len(priced)}")
    if priced:
        minutes = sorted(float(r["minutes_before"]) for r in priced)
        print(f"minutes_before: median {minutes[len(minutes)//2]}  max {max(minutes)}")
    complements = [float(r["complement_sum"]) for r in results if r["complement_sum"] != ""]
    if complements:
        print(f"complement sample n={len(complements)} min={min(complements):.4f} max={max(complements):.4f} mean={sum(complements)/len(complements):.4f}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
