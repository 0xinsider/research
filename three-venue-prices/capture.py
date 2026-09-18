#!/usr/bin/env python3
"""#14883. One capture of the same games on three venues.

Reads three public, unauthenticated endpoints in one run and writes the fields
the analysis uses, exactly as each provider returned them:

  Polymarket  gamma-api.polymarket.com/markets   (moneyline markets by league tag)
  Kalshi      api.elections.kalshi.com/trade-api/v2/events  (game series, nested markets)
  DraftKings  site.api.espn.com/.../scoreboard   (ESPN publishes the DraftKings line
              under odds[].provider.name == "DraftKings")

No value is converted here. Prices stay the strings or numbers the provider
sent; the analysis script owns every derived figure.

Usage:
  python3 capture.py OUT.json [--from YYYYMMDD --to YYYYMMDD]

The default window is today through two days out, in UTC.
"""

import argparse
import json
import sys
import time
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

USER_AGENT = "0xinsider-research/1.0 (+https://0xinsider.com/research)"

# League -> the three providers' own names for it. Polymarket tag ids come from
# gamma-api.polymarket.com/tags/slug/<slug>, read on 2026-09-18.
LEAGUES = {
    "nfl": {"espn": "football/nfl", "kalshi": "KXNFLGAME", "pm_tag_id": 450, "espn_extra": {}},
    "cfb": {
        "espn": "football/college-football",
        "kalshi": "KXNCAAFGAME",
        "pm_tag_id": 100351,
        # groups=80 is every FBS game; the default scoreboard is the top 25 only.
        "espn_extra": {"groups": "80", "limit": "400"},
    },
    "mlb": {"espn": "baseball/mlb", "kalshi": "KXMLBGAME", "pm_tag_id": 100381, "espn_extra": {}},
    "wnba": {"espn": "basketball/wnba", "kalshi": "KXWNBAGAME", "pm_tag_id": 100254, "espn_extra": {}},
}


def get_json(url: str, identify: bool = True):
    # ESPN's edge answers 403 to any user agent it does not recognise (a custom one and a
    # browser one on 2026-09-14, this script's own on 2026-09-18) and 200 to Python's default,
    # so the ESPN reads send no User-Agent header of their own. Kalshi and Polymarket get ours.
    headers = {"Accept": "application/json"}
    if identify:
        headers["User-Agent"] = USER_AGENT
    request = urllib.request.Request(url, headers=headers)
    last_error = None
    for attempt in range(4):
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.loads(response.read().decode("utf-8"))
        except Exception as error:  # noqa: BLE001 - retried, then raised below
            last_error = error
            time.sleep(1.5 * (attempt + 1))
    raise RuntimeError(f"GET {url} failed after 4 attempts: {last_error}")


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def close_or_none(side: dict | None, field: str):
    if not side:
        return None
    return (side.get("close") or {}).get(field)


def open_or_none(side: dict | None, field: str):
    if not side:
        return None
    return (side.get("open") or {}).get(field)


def espn_days(date_from: str, date_to: str) -> list[str]:
    day = datetime.strptime(date_from, "%Y%m%d")
    last = datetime.strptime(date_to, "%Y%m%d")
    days = []
    while day <= last:
        days.append(day.strftime("%Y%m%d"))
        day += timedelta(days=1)
    return days


def capture_espn(league: str, config: dict, date_from: str, date_to: str) -> dict:
    # One request per day: the NFL scoreboard answers 400 to a date range (2026-09-18).
    fetched_at = now_iso()
    urls = []
    events = []
    seen = set()
    for day in espn_days(date_from, date_to):
        params = {"dates": day, **config["espn_extra"]}
        url = f"https://site.api.espn.com/apis/site/v2/sports/{config['espn']}/scoreboard?{urllib.parse.urlencode(params)}"
        urls.append(url)
        for event in get_json(url, identify=False).get("events", []):
            if event.get("id") not in seen:
                seen.add(event.get("id"))
                events.append(event)
    games = []
    for event in events:
        competition = (event.get("competitions") or [{}])[0]
        teams = {}
        for competitor in competition.get("competitors", []):
            team = competitor.get("team") or {}
            teams[competitor.get("homeAway")] = {
                "abbreviation": team.get("abbreviation"),
                "location": team.get("location"),
                "name": team.get("name"),
                "displayName": team.get("displayName"),
                "shortDisplayName": team.get("shortDisplayName"),
            }
        odds_rows = []
        for odds in competition.get("odds") or []:
            moneyline = odds.get("moneyline") or {}
            spread = odds.get("pointSpread") or {}
            total = odds.get("total") or {}
            odds_rows.append(
                {
                    "provider": (odds.get("provider") or {}).get("name"),
                    "details": odds.get("details"),
                    "moneyline_home": close_or_none(moneyline.get("home"), "odds"),
                    "moneyline_away": close_or_none(moneyline.get("away"), "odds"),
                    "moneyline_home_open": open_or_none(moneyline.get("home"), "odds"),
                    "moneyline_away_open": open_or_none(moneyline.get("away"), "odds"),
                    "spread_home_line": close_or_none(spread.get("home"), "line"),
                    "spread_home_odds": close_or_none(spread.get("home"), "odds"),
                    "spread_away_line": close_or_none(spread.get("away"), "line"),
                    "spread_away_odds": close_or_none(spread.get("away"), "odds"),
                    "total_over_line": close_or_none(total.get("over"), "line"),
                    "total_over_odds": close_or_none(total.get("over"), "odds"),
                    "total_under_line": close_or_none(total.get("under"), "line"),
                    "total_under_odds": close_or_none(total.get("under"), "odds"),
                }
            )
        games.append(
            {
                "id": event.get("id"),
                "name": event.get("name"),
                "date": event.get("date"),
                "status": ((event.get("status") or {}).get("type") or {}).get("name"),
                "home": teams.get("home"),
                "away": teams.get("away"),
                "odds": odds_rows,
            }
        )
    return {"urls": urls, "fetched_at": fetched_at, "games": games}


def capture_kalshi(config: dict) -> dict:
    base = "https://api.elections.kalshi.com/trade-api/v2/events"
    fetched_at = now_iso()
    events = []
    cursor = ""
    urls = []
    while True:
        params = {
            "series_ticker": config["kalshi"],
            "status": "open",
            "with_nested_markets": "true",
            "limit": "200",
        }
        if cursor:
            params["cursor"] = cursor
        url = f"{base}?{urllib.parse.urlencode(params)}"
        urls.append(url)
        payload = get_json(url)
        for event in payload.get("events", []):
            events.append(
                {
                    "event_ticker": event.get("event_ticker"),
                    "title": event.get("title"),
                    "sub_title": event.get("sub_title"),
                    "markets": [
                        {
                            "ticker": market.get("ticker"),
                            "yes_sub_title": market.get("yes_sub_title"),
                            "status": market.get("status"),
                            "yes_bid_dollars": market.get("yes_bid_dollars"),
                            "yes_ask_dollars": market.get("yes_ask_dollars"),
                            "last_price_dollars": market.get("last_price_dollars"),
                            "volume_fp": market.get("volume_fp"),
                            "open_interest_fp": market.get("open_interest_fp"),
                            "occurrence_datetime": market.get("occurrence_datetime"),
                            "expected_expiration_time": market.get("expected_expiration_time"),
                        }
                        for market in event.get("markets") or []
                    ],
                }
            )
        cursor = payload.get("cursor") or ""
        if not cursor or not payload.get("events"):
            break
    return {"urls": urls, "fetched_at": fetched_at, "events": events}


def capture_polymarket(config: dict) -> dict:
    base = "https://gamma-api.polymarket.com/markets"
    fetched_at = now_iso()
    markets = []
    urls = []
    offset = 0
    while True:
        params = {
            "sports_market_types": "moneyline",
            "closed": "false",
            "tag_id": str(config["pm_tag_id"]),
            "limit": "100",
            "offset": str(offset),
        }
        url = f"{base}?{urllib.parse.urlencode(params)}"
        urls.append(url)
        page = get_json(url)
        for market in page:
            markets.append(
                {
                    "slug": market.get("slug"),
                    "question": market.get("question"),
                    "sportsMarketType": market.get("sportsMarketType"),
                    "outcomes": market.get("outcomes"),
                    "outcomePrices": market.get("outcomePrices"),
                    "bestBid": market.get("bestBid"),
                    "bestAsk": market.get("bestAsk"),
                    "spread": market.get("spread"),
                    "lastTradePrice": market.get("lastTradePrice"),
                    "volumeNum": market.get("volumeNum"),
                    "liquidityNum": market.get("liquidityNum"),
                    "gameStartTime": market.get("gameStartTime"),
                    "active": market.get("active"),
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
    parser.add_argument("--to", dest="date_to", default=(today + timedelta(days=2)).strftime("%Y%m%d"))
    args = parser.parse_args()

    capture = {"started_at": now_iso(), "window": [args.date_from, args.date_to], "leagues": {}}
    for league, config in LEAGUES.items():
        # The three reads for one league run back to back, so a league's three
        # prices sit within seconds of each other.
        capture["leagues"][league] = {
            "draftkings_via_espn": capture_espn(league, config, args.date_from, args.date_to),
            "kalshi": capture_kalshi(config),
            "polymarket": capture_polymarket(config),
        }
        counts = capture["leagues"][league]
        print(
            f"{league}: espn_games={len(counts['draftkings_via_espn']['games'])} "
            f"kalshi_events={len(counts['kalshi']['events'])} "
            f"polymarket_moneylines={len(counts['polymarket']['markets'])}",
            file=sys.stderr,
        )
    capture["finished_at"] = now_iso()
    with open(args.out, "w", encoding="utf-8") as handle:
        json.dump(capture, handle, indent=1, sort_keys=True)
        handle.write("\n")
    print(f"wrote {args.out} ({capture['started_at']} to {capture['finished_at']})", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
