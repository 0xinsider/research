"""Dollars traded on each football moneyline before kickoff, from Polymarket's public trade history (#22229).

WHY. The September 14 analysis kept a game when `volume_usd` in the export was 10,000 or more. That column is
`markets.volume`, Polymarket's final reported volume for the market. It is wrong for a kickoff study twice over:
it counts the trading during the game, which nobody choosing a game before kickoff can see, and it is counted
in shares, not dollars (Gamma's `volumeNum` is the sum of taker `size`, #22291). This script measures what a
bettor could have known at the cutoff: the dollars that changed hands on the moneyline before it.

Input: football-games.csv (the read-only export) and football-prices.csv
(its `cutoff_utc` is the earlier of the market's scheduled start and ESPN's listed start, the same instant the
kickoff price is read at).
For each game it reads every taker trade at or before the cutoff:
  GET https://data-api.polymarket.com/trades?market=<condition_id>&takerOnly=true&limit=1000&end=<cutoff>
Taker trades count each fill once; `takerOnly=true` is the API's default and the basis of Polymarket's own
volume. Trades come newest first. The API refuses an offset past 10,000, so the script pages by time instead:
it keeps a batch's trades newer than the batch's oldest second and asks again with `end` at that second (`end`
is inclusive), so a second split across two batches is read whole once. A second holding a full batch on its
own is paged by offset.
  pregame_usd     sum of size x price over those trades (USDC)
  pregame_shares  sum of size
  pregame_trades  how many trades
  final_shares    the export's `volume_usd`, which is Polymarket's final volume in shares
Check: for a fixed sample of 40 games whose final volume is under 200,000 shares, it also reads the whole
history (no `end`) and reports how far the summed taker shares sit from `final_shares`. A match confirms that
taker trades are the basis the export's column counted.

Output: football-pregame-volume-2026-10-10.csv and a summary on stdout.
Usage: python3 football-pregame-volume-2026-10-10.py football-games.csv \
    football-prices.csv football-pregame-volume-2026-10-10.csv
"""

import csv
import json
import random
import sys
import threading
import time
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone

TRADES = "https://data-api.polymarket.com/trades"
BATCH = 1000
MAX_OFFSET = 10_000
SAMPLE_SEED = 20261010
SAMPLE_SIZE = 40
SAMPLE_MAX_SHARES = 200_000
pace = threading.Semaphore(4)


def fetch(params):
    url = f"{TRADES}?{urllib.parse.urlencode(params)}"
    request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (0xinsider research)"})
    for attempt in range(6):
        try:
            with pace:
                with urllib.request.urlopen(request, timeout=60) as response:
                    payload = json.load(response)
                time.sleep(0.3)
            if not isinstance(payload, list):
                raise RuntimeError(f"unexpected payload: {str(payload)[:200]}")
            return payload
        except Exception as error:  # a transient network or rate-limit error is retried, the sixth failure raises
            if attempt == 5:
                raise
            print(f"retry {params.get('market', '')[:12]}: {error}", file=sys.stderr)
            time.sleep(3 * (attempt + 1))
    raise RuntimeError("unreachable")


def one_second(market, second):
    """Every taker trade in one second, paged by offset (a second that fills a whole batch)."""
    trades, offset = [], 0
    while True:
        if offset > MAX_OFFSET:
            raise RuntimeError(f"{market}: more than {MAX_OFFSET} trades in second {second}")
        batch = fetch({"market": market, "takerOnly": "true", "limit": BATCH, "offset": offset, "start": second, "end": second})
        trades.extend(t for t in batch if t["timestamp"] == second)
        if len(batch) < BATCH:
            return trades
        offset += BATCH


def taker_trades(market, end=None):
    """Every taker trade at or before `end` (epoch seconds), or the whole history when `end` is None."""
    trades, cursor, requests = [], end, 0
    while True:
        params = {"market": market, "takerOnly": "true", "limit": BATCH}
        if cursor is not None:
            params["end"] = cursor
        batch = fetch(params)
        requests += 1
        if cursor is not None:
            batch = [t for t in batch if t["timestamp"] <= cursor]
        if len(batch) < BATCH:
            trades.extend(batch)
            return trades, requests
        oldest = min(t["timestamp"] for t in batch)
        if oldest == max(t["timestamp"] for t in batch):
            trades.extend(one_second(market, oldest))
            if oldest == 0:
                return trades, requests
            cursor = oldest - 1
            continue
        trades.extend(t for t in batch if t["timestamp"] > oldest)
        cursor = oldest


def utc_seconds(text):
    return int(datetime.strptime(text, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).timestamp())


def main(games_path, prices_path, output_path):
    games = list(csv.DictReader(open(games_path)))
    cutoff = {row["condition_id"]: row["cutoff_utc"] for row in csv.DictReader(open(prices_path))}
    small = [game for game in games if float(game["volume_usd"]) < SAMPLE_MAX_SHARES]
    sample_ids = set(game["condition_id"] for game in random.Random(SAMPLE_SEED).sample(small, SAMPLE_SIZE))

    def work(game):
        condition_id = game["condition_id"]
        trades, requests = taker_trades(condition_id, utc_seconds(cutoff[condition_id]))
        row = {
            "condition_id": condition_id,
            "event_slug": game["event_slug"],
            "cutoff_utc": cutoff[condition_id],
            "pregame_trades": len(trades),
            "pregame_shares": round(sum(float(t["size"]) for t in trades), 6),
            "pregame_usd": round(sum(float(t["size"]) * float(t["price"]) for t in trades), 2),
            "final_shares": game["volume_usd"],
            "requests": requests,
            "all_time_shares": "",
        }
        if condition_id in sample_ids:
            history, _ = taker_trades(condition_id)
            row["all_time_shares"] = round(sum(float(t["size"]) for t in history), 6)
        return row

    started = datetime.now(timezone.utc).isoformat(timespec="seconds")
    with ThreadPoolExecutor(max_workers=4) as pool:
        rows = list(pool.map(work, games))

    with open(output_path, "w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)

    print(f"run_at {started}  finished {datetime.now(timezone.utc).isoformat(timespec='seconds')}")
    print(f"games {len(rows)}  requests {sum(row['requests'] for row in rows)}  taker_trades_before_cutoff {sum(row['pregame_trades'] for row in rows)}")
    usd = sorted(row["pregame_usd"] for row in rows)
    print(f"pregame_usd: median {usd[len(usd) // 2]:,.2f}  p10 {usd[len(usd) // 10]:,.2f}  p90 {usd[int(len(usd) * 0.9)]:,.2f}")
    for floor in (10_000, 50_000):
        print(f"pregame_usd >= {floor:,}: {sum(1 for value in usd if value >= floor)}  final_shares >= {floor:,}: {sum(1 for row in rows if float(row['final_shares']) >= floor)}")
    checked = [row for row in rows if row["all_time_shares"] != ""]
    if checked:
        gaps = sorted(abs(row["all_time_shares"] - float(row["final_shares"])) / max(float(row["final_shares"]), 1) for row in checked)
        within = sum(1 for gap in gaps if gap <= 0.01)
        print(f"check {len(checked)} games: all-time taker shares within 1% of final_shares {within}; gap median {100 * gaps[len(gaps) // 2]:.3f}%  max {100 * gaps[-1]:.3f}%")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3])
