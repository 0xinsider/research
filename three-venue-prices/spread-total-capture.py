#!/usr/bin/env python3
"""#14901. One capture of spread and total lines: Polymarket's ladders and the DraftKings line.

The companion to capture.py (#14883), which covered
moneylines. It reuses that script's ESPN reader, which already saves the
DraftKings spread line, total line and the price on each side, and adds
Polymarket's `spreads` and `totals` markets for the same leagues.

Polymarket lists a ladder on each game: one market per half-point line, each
with its own order book. Nothing is converted here; the analysis script owns
every derived figure.

Usage:
  python3 spread-total-capture.py OUT.json [--from YYYYMMDD --to YYYYMMDD]
"""

import argparse
import importlib.util
import json
import sys
import urllib.parse
from datetime import datetime, timedelta, timezone
from pathlib import Path

# Loading the sibling script below would otherwise leave a __pycache__ beside the evidence.
sys.dont_write_bytecode = True

_BASE = Path(__file__).resolve().parent / "capture.py"
_spec = importlib.util.spec_from_file_location("three_venue_capture", _BASE)
if _spec is None or _spec.loader is None:
    raise RuntimeError(f"cannot load {_BASE}")
base = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(base)

# The WNBA is left out: its slate in this window is three playoff games.
LEAGUES = {key: base.LEAGUES[key] for key in ("nfl", "cfb", "mlb")}
MARKET_TYPES = ("spreads", "totals")


def capture_polymarket_ladders(config: dict, start_min: datetime, start_max: datetime) -> dict:
    url_base = "https://gamma-api.polymarket.com/markets"
    fetched_at = base.now_iso()
    markets, urls = [], []
    for market_type in MARKET_TYPES:
        offset = 0
        while True:
            params = {
                "sports_market_types": market_type,
                "closed": "false",
                "tag_id": str(config["pm_tag_id"]),
                # endDate is the start for football and a week later for baseball, so the window
                # is wide and the analysis filters on gameStartTime.
                "end_date_min": start_min.strftime("%Y-%m-%dT%H:%M:%SZ"),
                "end_date_max": (start_max + timedelta(days=9)).strftime("%Y-%m-%dT%H:%M:%SZ"),
                "limit": "100",
                "offset": str(offset),
            }
            url = f"{url_base}?{urllib.parse.urlencode(params)}"
            urls.append(url)
            page = base.get_json(url)
            for market in page:
                start = market.get("gameStartTime")
                if not start:
                    continue
                markets.append(
                    {
                        "slug": market.get("slug"),
                        "question": market.get("question"),
                        "sportsMarketType": market.get("sportsMarketType"),
                        "line": market.get("line"),
                        "outcomes": market.get("outcomes"),
                        "outcomePrices": market.get("outcomePrices"),
                        "bestBid": market.get("bestBid"),
                        "bestAsk": market.get("bestAsk"),
                        "volumeNum": market.get("volumeNum"),
                        "liquidityNum": market.get("liquidityNum"),
                        "gameStartTime": start,
                        "acceptingOrders": market.get("acceptingOrders"),
                    }
                )
            if len(page) < 100:
                break
            offset += 100
    return {"urls": urls, "fetched_at": fetched_at, "markets": markets}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("out")
    today = datetime.now(timezone.utc)
    parser.add_argument("--from", dest="date_from", default=today.strftime("%Y%m%d"))
    parser.add_argument("--to", dest="date_to", default=(today + timedelta(days=3)).strftime("%Y%m%d"))
    args = parser.parse_args()
    start_min = datetime.strptime(args.date_from, "%Y%m%d").replace(tzinfo=timezone.utc)
    start_max = datetime.strptime(args.date_to, "%Y%m%d").replace(tzinfo=timezone.utc) + timedelta(days=1)

    capture = {"started_at": base.now_iso(), "window": [args.date_from, args.date_to], "leagues": {}}
    for league, config in LEAGUES.items():
        espn = base.capture_espn(league, config, args.date_from, args.date_to)
        ladders = capture_polymarket_ladders(config, start_min, start_max)
        capture["leagues"][league] = {"draftkings_via_espn": espn, "polymarket": ladders}
        print(f"{league}: espn_games={len(espn['games'])} polymarket_lines={len(ladders['markets'])}", file=sys.stderr)
    capture["finished_at"] = base.now_iso()
    with open(args.out, "w", encoding="utf-8") as handle:
        json.dump(capture, handle, indent=1, sort_keys=True)
        handle.write("\n")
    print(f"wrote {args.out} ({capture['started_at']} to {capture['finished_at']})", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
