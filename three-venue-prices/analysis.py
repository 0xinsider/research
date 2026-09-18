#!/usr/bin/env python3
"""#14883. Join one three-venue capture by game and measure the price gaps.

Input is the JSON capture.py writes. Every figure the
study at /research/use-0xinsider-for-kalshi-draftkings states comes from this
script's output.

A game enters the universe when all of these hold at capture time:

  * ESPN lists it as scheduled, with a start after the capture, and publishes a
    DraftKings moneyline with a number on both sides (ESPN prints "OFF" when
    DraftKings has the line down).
  * Polymarket lists a game moneyline for it (slug <league>-<away>-<home>-<date>)
    that is accepting orders, with a best bid and a best ask.
  * Kalshi lists an open game event for it with a bid and an ask on the home
    side's market.
  * The pairing is unique. A doubleheader, where one date holds the same two
    teams twice, is dropped rather than guessed.

Every probability is the HOME team's. Definitions:

  Polymarket  midpoint of bestBid and bestAsk on the moneyline market, read for
              the home outcome (the book quotes outcome 0; outcome 1 is 1 - x).
  Kalshi      midpoint of yes_bid_dollars and yes_ask_dollars on the home team's
              market.
  DraftKings  American odds to implied probability, p = 100 / (odds + 100) for a
              plus price and |odds| / (|odds| + 100) for a minus price. The two
              sides sum to more than 1; the excess is the overround. The fair
              probability divides each side by the sum (proportional method).
              Section 2 also reports the equal-cents method, which subtracts
              half the overround from each side.

Gaps are in percentage points. The Polymarket taker fee is the published sports
schedule, 0.05 x price x (1 - price) per share (docs.polymarket.com changelog,
2026-07-10). No Kalshi fee is modelled: its schedule was not readable from an
official source at capture time, so the Kalshi cost shown is the quoted spread
alone and the study says so.

Usage:
  python3 analysis.py CAPTURE.json [--csv games.csv] [--ts data.ts]
"""

import argparse
import csv
import json
import re
import statistics
import sys
from datetime import datetime, timedelta, timezone

LEAGUE_LABEL = {"nfl": "NFL", "cfb": "College football", "mlb": "MLB", "wnba": "WNBA"}
POLYMARKET_SPORTS_FEE = 0.05
# US Eastern is UTC-4 on every date this capture can hold (September, daylight time).
EASTERN = timezone(timedelta(hours=-4))
MONTHS = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]


def parse_utc(text: str) -> datetime:
    cleaned = text.strip().replace(" ", "T").replace("Z", "+00:00")
    if re.search(r"[+-]\d{2}$", cleaned):
        cleaned += ":00"
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}\+00:00", cleaned):
        cleaned = cleaned.replace("+00:00", ":00+00:00")
    return datetime.fromisoformat(cleaned).astimezone(timezone.utc)


def tokens(name: str) -> set[str]:
    lowered = name.lower().replace("&", " and ")
    lowered = re.sub(r"\bst\.?(?=\s|$)", "state", lowered)
    lowered = re.sub(r"[^a-z0-9 ]+", " ", lowered)
    return {token for token in lowered.split() if token}


def team_names(team: dict) -> list[str]:
    return [team[key] for key in ("location", "shortDisplayName", "displayName", "name", "abbreviation") if team.get(key)]


def name_matches(label: str, team: dict) -> bool:
    """True when a venue's label names this ESPN team.

    Equal token sets, or one a subset of the other, against any ESPN name form.
    A single-letter token ("Chicago C", "Los Angeles R") must be the initial of a
    word in the team's full name.
    """
    wanted = tokens(label)
    if not wanted:
        return False
    full = tokens(team.get("displayName") or "")
    letters = {token for token in wanted if len(token) == 1}
    words = wanted - letters
    if letters and not all(any(word.startswith(letter) for word in full) for letter in letters):
        return False
    if not words:
        return False
    for form in team_names(team):
        have = tokens(form)
        if words == have or words <= have or have <= words:
            return True
    return False


def american_to_implied(odds: str) -> float | None:
    text = (odds or "").strip().upper()
    if text in ("", "OFF", "N/A"):
        return None
    if text in ("EVEN", "EV"):
        return 0.5
    try:
        value = float(text)
    except ValueError:
        return None
    if value > 0:
        return 100.0 / (value + 100.0)
    return abs(value) / (abs(value) + 100.0)


def to_float(value) -> float | None:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def polymarket_home(market: dict, home: dict, away: dict):
    """(home_mid, spread, volume) or None when the market does not pair with the game."""
    outcomes = json.loads(market.get("outcomes") or "[]")
    if len(outcomes) != 2:
        return None
    bid, ask = to_float(market.get("bestBid")), to_float(market.get("bestAsk"))
    if bid is None or ask is None or ask <= bid or not market.get("acceptingOrders"):
        return None
    first_home = name_matches(outcomes[0], home) and name_matches(outcomes[1], away)
    first_away = name_matches(outcomes[0], away) and name_matches(outcomes[1], home)
    if first_home == first_away:
        return None
    mid_first = (bid + ask) / 2.0
    return (mid_first if first_home else 1.0 - mid_first, ask - bid, to_float(market.get("volumeNum")) or 0.0)


def kalshi_home(event: dict, home: dict, away: dict):
    markets = event.get("markets") or []
    if len(markets) != 2:
        return None
    home_market = [m for m in markets if name_matches(m.get("yes_sub_title") or "", home)]
    away_market = [m for m in markets if name_matches(m.get("yes_sub_title") or "", away)]
    if len(home_market) != 1 or len(away_market) != 1 or home_market[0] is away_market[0]:
        return None
    bid, ask = to_float(home_market[0].get("yes_bid_dollars")), to_float(home_market[0].get("yes_ask_dollars"))
    if bid is None or ask is None or ask <= bid or bid <= 0.0 or ask >= 1.0:
        return None
    volume = sum(to_float(m.get("volume_fp")) or 0.0 for m in markets)
    return ((bid + ask) / 2.0, ask - bid, volume)


def kalshi_date_code(start: datetime) -> str:
    local = start.astimezone(EASTERN)
    return f"{local.year % 100:02d}{MONTHS[local.month - 1]}{local.day:02d}"


def build_rows(capture: dict):
    started = parse_utc(capture["started_at"])
    rows, funnel = [], {}
    for league, venues in capture["leagues"].items():
        counts = {"espn_scheduled": 0, "draftkings_moneyline": 0, "polymarket": 0, "kalshi": 0, "all_three": 0, "ambiguous": 0}
        slug_pattern = re.compile(rf"^{league}-[a-z0-9]+-[a-z0-9]+-\d{{4}}-\d{{2}}-\d{{2}}$")
        pm_markets = [m for m in venues["polymarket"]["markets"] if slug_pattern.match(m.get("slug") or "") and m.get("gameStartTime")]
        games = venues["draftkings_via_espn"]["games"]
        pair_counts = {}
        for game in games:
            if game.get("home") and game.get("away"):
                key = (kalshi_date_code(parse_utc(game["date"])), game["home"]["abbreviation"], game["away"]["abbreviation"])
                pair_counts[key] = pair_counts.get(key, 0) + 1
        for game in games:
            home, away = game.get("home"), game.get("away")
            if not home or not away or game.get("status") != "STATUS_SCHEDULED":
                continue
            start = parse_utc(game["date"])
            if start <= started:
                continue
            counts["espn_scheduled"] += 1
            line = next((o for o in game.get("odds") or [] if o.get("provider") == "DraftKings"), None)
            implied_home = american_to_implied(line.get("moneyline_home")) if line else None
            implied_away = american_to_implied(line.get("moneyline_away")) if line else None
            if implied_home is None or implied_away is None:
                continue
            counts["draftkings_moneyline"] += 1
            date_code = kalshi_date_code(start)
            if pair_counts.get((date_code, home["abbreviation"], away["abbreviation"]), 0) > 1:
                counts["ambiguous"] += 1
                continue

            pm_hits = []
            for market in pm_markets:
                if abs((parse_utc(market["gameStartTime"]) - start).total_seconds()) > 5400:
                    continue
                result = polymarket_home(market, home, away)
                if result:
                    pm_hits.append((market, result))
            kalshi_hits = []
            for event in venues["kalshi"]["events"]:
                if date_code not in (event.get("event_ticker") or ""):
                    continue
                result = kalshi_home(event, home, away)
                if result:
                    kalshi_hits.append((event, result))
            if len(pm_hits) > 1 or len(kalshi_hits) > 1:
                counts["ambiguous"] += 1
                continue
            if pm_hits:
                counts["polymarket"] += 1
            if kalshi_hits:
                counts["kalshi"] += 1
            if not pm_hits or not kalshi_hits:
                continue
            counts["all_three"] += 1

            (pm_market, (pm_mid, pm_spread, pm_volume)) = pm_hits[0]
            (kalshi_event, (k_mid, k_spread, k_volume)) = kalshi_hits[0]
            total_implied = implied_home + implied_away
            dk_fair = implied_home / total_implied
            # The other common way to take the margin out: the same number of cents off each side.
            dk_equal = implied_home - (total_implied - 1.0) / 2.0
            favorite_is_home = dk_fair >= 0.5
            # What the favorite costs a buyer who takes the quoted price, in cents per $1 of payout.
            fav_mid = pm_mid if favorite_is_home else 1.0 - pm_mid
            pm_fav_ask = fav_mid + pm_spread / 2.0
            pm_fav_all_in = pm_fav_ask + POLYMARKET_SPORTS_FEE * pm_fav_ask * (1.0 - pm_fav_ask)
            k_fav_mid = k_mid if favorite_is_home else 1.0 - k_mid
            dk_fav_implied = implied_home if favorite_is_home else implied_away
            dk_dog_implied = implied_away if favorite_is_home else implied_home
            pm_dog_ask = (1.0 - fav_mid) + pm_spread / 2.0
            pm_dog_all_in = pm_dog_ask + POLYMARKET_SPORTS_FEE * pm_dog_ask * (1.0 - pm_dog_ask)
            rows.append(
                {
                    "league": league,
                    "game": game["name"],
                    "game_short": f"{away.get('shortDisplayName') or away['displayName']} at {home.get('shortDisplayName') or home['displayName']}",
                    "start_utc": start.strftime("%Y-%m-%dT%H:%MZ"),
                    "polymarket_slug": pm_market["slug"],
                    "kalshi_event": kalshi_event["event_ticker"],
                    "dk_home": line["moneyline_home"],
                    "dk_away": line["moneyline_away"],
                    "dk_overround_pts": (total_implied - 1.0) * 100.0,
                    "dk_fair_home_pct": dk_fair * 100.0,
                    "pm_home_pct": pm_mid * 100.0,
                    "kalshi_home_pct": k_mid * 100.0,
                    "pm_spread_c": pm_spread * 100.0,
                    "kalshi_spread_c": k_spread * 100.0,
                    "pm_volume_usd": pm_volume,
                    "kalshi_volume_contracts": k_volume,
                    "gap_pm_kalshi": (pm_mid - k_mid) * 100.0,
                    "gap_pm_dk": (pm_mid - dk_fair) * 100.0,
                    "dk_equal_home_pct": dk_equal * 100.0,
                    "gap_pm_dk_equal": (pm_mid - dk_equal) * 100.0,
                    "gap_kalshi_dk": (k_mid - dk_fair) * 100.0,
                    "fav_dk_fair_pct": max(dk_fair, 1.0 - dk_fair) * 100.0,
                    "fav_gap_pm_dk": (fav_mid - max(dk_fair, 1.0 - dk_fair)) * 100.0,
                    "fav_dk_price_c": dk_fav_implied * 100.0,
                    "fav_pm_ask_c": pm_fav_ask * 100.0,
                    "fav_pm_all_in_c": pm_fav_all_in * 100.0,
                    "fav_kalshi_ask_c": (k_fav_mid + k_spread / 2.0) * 100.0,
                    "pm_both_sides_taker_c": (pm_fav_all_in + pm_dog_all_in - 1.0) * 100.0,
                    "dog_dk_price_c": dk_dog_implied * 100.0,
                    "dog_pm_ask_c": pm_dog_ask * 100.0,
                    "dog_pm_all_in_c": pm_dog_all_in * 100.0,
                    "dog_kalshi_ask_c": ((1.0 - k_fav_mid) + k_spread / 2.0) * 100.0,
                }
            )
        funnel[league] = counts
    return rows, funnel


def pearson(xs, ys) -> float:
    mean_x, mean_y = statistics.fmean(xs), statistics.fmean(ys)
    cov = sum((x - mean_x) * (y - mean_y) for x, y in zip(xs, ys))
    var_x = sum((x - mean_x) ** 2 for x in xs)
    var_y = sum((y - mean_y) ** 2 for y in ys)
    return cov / (var_x * var_y) ** 0.5


def quantile(values, q: float) -> float:
    ordered = sorted(values)
    position = (len(ordered) - 1) * q
    low = int(position)
    high = min(low + 1, len(ordered) - 1)
    return ordered[low] + (ordered[high] - ordered[low]) * (position - low)


def gap_summary(label: str, gaps: list[float]) -> None:
    absolute = [abs(g) for g in gaps]
    n = len(gaps)
    print(
        f"  {label:<24} n={n:>3}  median|gap|={statistics.median(absolute):5.2f}  mean|gap|={statistics.fmean(absolute):5.2f}  "
        f"p90|gap|={quantile(absolute, 0.9):5.2f}  max|gap|={max(absolute):5.2f}  mean signed={statistics.fmean(gaps):+5.2f}  "
        f"within1={100.0 * sum(a <= 1.0 for a in absolute) / n:5.1f}%  within2={100.0 * sum(a <= 2.0 for a in absolute) / n:5.1f}%  "
        f"within3={100.0 * sum(a <= 3.0 for a in absolute) / n:5.1f}%"
    )


BANDS = [("50to60", "50 to 60%", 50.0, 60.0), ("60to75", "60 to 75%", 60.0, 75.0), ("75to90", "75 to 90%", 75.0, 90.0), ("90up", "90% and up", 90.0, 100.1)]


def gap_stats(gaps: list[float]) -> dict:
    absolute = [abs(g) for g in gaps]
    n = len(gaps)
    return {
        "n": n,
        "medianAbs": statistics.median(absolute),
        "meanAbs": statistics.fmean(absolute),
        "p90Abs": quantile(absolute, 0.9),
        "maxAbs": max(absolute),
        "meanSigned": statistics.fmean(gaps),
        "within1Pct": 100.0 * sum(a <= 1.0 for a in absolute) / n,
        "within2Pct": 100.0 * sum(a <= 2.0 for a in absolute) / n,
        "within3Pct": 100.0 * sum(a <= 3.0 for a in absolute) / n,
    }


def side_stats(rows: list[dict], side: str) -> dict:
    ask = [r[f"{side}_dk_price_c"] - r[f"{side}_pm_ask_c"] for r in rows]
    all_in = [r[f"{side}_dk_price_c"] - r[f"{side}_pm_all_in_c"] for r in rows]
    kalshi = [r[f"{side}_dk_price_c"] - r[f"{side}_kalshi_ask_c"] for r in rows]
    share = [100.0 * (r[f"{side}_dk_price_c"] - r[f"{side}_pm_all_in_c"]) / r[f"{side}_dk_price_c"] for r in rows]
    return {
        "dkMinusPmAskMedian": statistics.median(ask),
        "dkMinusPmAllInMedian": statistics.median(all_in),
        "dkMinusKalshiAskMedian": statistics.median(kalshi),
        "pmCheaperGames": sum(d > 0 for d in all_in),
        "shareOfDkPriceMedianPct": statistics.median(share),
    }


def summarize(capture: dict, rows: list[dict], funnel: dict) -> dict:
    """Every aggregate the web evidence module carries, from the same rows the report prints."""
    overround = [r["dk_overround_pts"] for r in rows]
    both = [r["pm_both_sides_taker_c"] for r in rows]
    favorite_gaps = [r["fav_gap_pm_dk"] for r in rows]
    return {
        "capturedAt": capture["started_at"],
        "finishedAt": capture["finished_at"],
        "funnel": [
            {
                "key": league,
                "label": LEAGUE_LABEL[league],
                "scheduled": counts["espn_scheduled"],
                "draftKingsLine": counts["draftkings_moneyline"],
                "polymarket": counts["polymarket"],
                "kalshi": counts["kalshi"],
                "allThree": counts["all_three"],
                "ambiguous": counts["ambiguous"],
            }
            for league, counts in funnel.items()
        ],
        "gaps": {
            "pmKalshi": gap_stats([r["gap_pm_kalshi"] for r in rows]),
            "pmDk": gap_stats([r["gap_pm_dk"] for r in rows]),
            "kalshiDk": gap_stats([r["gap_kalshi_dk"] for r in rows]),
            "pmDkEqualCents": gap_stats([r["gap_pm_dk_equal"] for r in rows]),
        },
        "correlation": {
            "pmKalshi": pearson([r["pm_home_pct"] for r in rows], [r["kalshi_home_pct"] for r in rows]),
            "pmDk": pearson([r["pm_home_pct"] for r in rows], [r["dk_fair_home_pct"] for r in rows]),
        },
        "sameFavoriteGames": sum((r["pm_home_pct"] >= 50.0) == (r["dk_fair_home_pct"] >= 50.0) == (r["kalshi_home_pct"] >= 50.0) for r in rows),
        "identicalMidGames": sum(abs(r["gap_pm_kalshi"]) < 1e-9 for r in rows),
        "byLeague": [
            {
                "key": league,
                "label": LEAGUE_LABEL[league],
                "pmKalshi": gap_stats([r["gap_pm_kalshi"] for r in rows if r["league"] == league]),
                "pmDk": gap_stats([r["gap_pm_dk"] for r in rows if r["league"] == league]),
                "dkOverroundMedian": statistics.median([r["dk_overround_pts"] for r in rows if r["league"] == league]),
            }
            for league in funnel
            if any(r["league"] == league for r in rows)
        ],
        "byBand": [
            {
                "key": key,
                "label": label,
                "pmKalshi": gap_stats([r["gap_pm_kalshi"] for r in rows if low <= r["fav_dk_fair_pct"] < high]),
                "pmDk": gap_stats([r["gap_pm_dk"] for r in rows if low <= r["fav_dk_fair_pct"] < high]),
                "favoriteSignedMean": statistics.fmean([r["fav_gap_pm_dk"] for r in rows if low <= r["fav_dk_fair_pct"] < high]),
                "pmHigherOnFavorite": sum(r["fav_gap_pm_dk"] > 0 for r in rows if low <= r["fav_dk_fair_pct"] < high),
                "dkOverroundMedian": statistics.median([r["dk_overround_pts"] for r in rows if low <= r["fav_dk_fair_pct"] < high]),
                "pmBothSidesTakerMedian": statistics.median([r["pm_both_sides_taker_c"] for r in rows if low <= r["fav_dk_fair_pct"] < high]),
            }
            for key, label, low, high in BANDS
            if any(low <= r["fav_dk_fair_pct"] < high for r in rows)
        ],
        "favoriteSigned": {"mean": statistics.fmean(favorite_gaps), "pmHigherGames": sum(g > 0 for g in favorite_gaps)},
        "cost": {
            "dkOverroundMedian": statistics.median(overround),
            "dkOverroundMean": statistics.fmean(overround),
            "dkOverroundMin": min(overround),
            "dkOverroundMax": max(overround),
            "pmSpreadMedian": statistics.median([r["pm_spread_c"] for r in rows]),
            "pmSpreadMean": statistics.fmean([r["pm_spread_c"] for r in rows]),
            "pmSpreadMax": max(r["pm_spread_c"] for r in rows),
            "kalshiSpreadMedian": statistics.median([r["kalshi_spread_c"] for r in rows]),
            "kalshiSpreadMean": statistics.fmean([r["kalshi_spread_c"] for r in rows]),
            "kalshiSpreadMax": max(r["kalshi_spread_c"] for r in rows),
            "pmBothSidesTakerMedian": statistics.median(both),
            "pmBothSidesTakerMean": statistics.fmean(both),
            "pmBothSidesTakerMin": min(both),
            "pmBothSidesTakerMax": max(both),
            "pmCheaperThanOverroundGames": sum(r["pm_both_sides_taker_c"] < r["dk_overround_pts"] for r in rows),
        },
        "sides": {"favorite": side_stats(rows, "fav"), "underdog": side_stats(rows, "dog")},
        "volume": {
            "pmUsd": sum(r["pm_volume_usd"] for r in rows),
            "pmMedianUsd": statistics.median([r["pm_volume_usd"] for r in rows]),
            "kalshiContracts": sum(r["kalshi_volume_contracts"] for r in rows),
            "kalshiMedianContracts": statistics.median([r["kalshi_volume_contracts"] for r in rows]),
        },
        "games": [
            {
                "league": r["league"],
                "game": r["game"],
                "gameShort": r["game_short"],
                "startUtc": r["start_utc"],
                "polymarketSlug": r["polymarket_slug"],
                "dkHome": r["dk_home"],
                "dkAway": r["dk_away"],
                "dkFairHomePct": r["dk_fair_home_pct"],
                "pmHomePct": r["pm_home_pct"],
                "kalshiHomePct": r["kalshi_home_pct"],
                "dkOverroundPts": r["dk_overround_pts"],
            }
            for r in sorted(rows, key=lambda r: (r["league"], r["start_utc"], r["game"]))
        ],
    }


def rounded(value, digits: int = 4):
    if isinstance(value, float):
        return round(value, digits)
    if isinstance(value, dict):
        return {key: rounded(item, digits) for key, item in value.items()}
    if isinstance(value, list):
        return [rounded(item, digits) for item in value]
    return value


def write_ts(path: str, summary: dict) -> None:
    body = json.dumps(rounded(summary), indent=2)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(
            "// GENERATED FILE -- DO NOT EDIT BY HAND.\n"
            "//\n"
            "// #14883. Every aggregate and every matched game behind\n"
            "// /research/use-0xinsider-for-kalshi-draftkings, to four decimal places.\n"
            "//\n"
            "// Regenerate, from the repository root:\n"
            "//   V=docs/research-articles/verification\n"
            "//   python3 $V/analysis.py $V/2026-09-18-three-venue-capture.json \\\n"
            "//     --ts web/src/lib/research-evidence/three-venue-prices.data.ts\n"
            "// A clean `git diff` after that command is the check that this file matches the capture.\n"
            "\n"
            f"export const THREE_VENUE_DATA = {body};\n"
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("capture")
    parser.add_argument("--csv")
    parser.add_argument("--ts", help="write the web evidence data module")
    args = parser.parse_args()
    with open(args.capture, encoding="utf-8") as handle:
        capture = json.load(handle)
    rows, funnel = build_rows(capture)

    print(f"capture {capture['started_at']} to {capture['finished_at']}")
    print("\n1. Funnel by league (games)")
    print(f"  {'league':<18}{'scheduled':>10}{'DK line':>9}{'+Polymkt':>10}{'+Kalshi':>9}{'all three':>11}{'ambiguous':>11}")
    totals = {}
    for league, counts in funnel.items():
        print(
            f"  {LEAGUE_LABEL[league]:<18}{counts['espn_scheduled']:>10}{counts['draftkings_moneyline']:>9}{counts['polymarket']:>10}"
            f"{counts['kalshi']:>9}{counts['all_three']:>11}{counts['ambiguous']:>11}"
        )
        for key, value in counts.items():
            totals[key] = totals.get(key, 0) + value
    print(
        f"  {'Total':<18}{totals['espn_scheduled']:>10}{totals['draftkings_moneyline']:>9}{totals['polymarket']:>10}"
        f"{totals['kalshi']:>9}{totals['all_three']:>11}{totals['ambiguous']:>11}"
    )
    if not rows:
        print("no games matched on all three venues")
        return 1

    print("\n2. Gap between venues, home-team probability, percentage points")
    gap_summary("Polymarket - Kalshi", [r["gap_pm_kalshi"] for r in rows])
    gap_summary("Polymarket - DraftKings", [r["gap_pm_dk"] for r in rows])
    gap_summary("Kalshi - DraftKings", [r["gap_kalshi_dk"] for r in rows])
    print(" the DraftKings margin removed as equal cents off each side instead of proportionally")
    gap_summary("Polymarket - DraftKings", [r["gap_pm_dk_equal"] for r in rows])
    print(f"  correlation Polymarket vs Kalshi     r={pearson([r['pm_home_pct'] for r in rows], [r['kalshi_home_pct'] for r in rows]):.4f}")
    print(f"  correlation Polymarket vs DraftKings r={pearson([r['pm_home_pct'] for r in rows], [r['dk_fair_home_pct'] for r in rows]):.4f}")
    same_favorite = sum((r["pm_home_pct"] >= 50.0) == (r["dk_fair_home_pct"] >= 50.0) == (r["kalshi_home_pct"] >= 50.0) for r in rows)
    print(f"  all three name the same favorite in {same_favorite} of {len(rows)} games")

    print("\n3. The same, by league")
    for league in funnel:
        subset = [r for r in rows if r["league"] == league]
        if not subset:
            continue
        print(f" {LEAGUE_LABEL[league]}")
        gap_summary("Polymarket - Kalshi", [r["gap_pm_kalshi"] for r in subset])
        gap_summary("Polymarket - DraftKings", [r["gap_pm_dk"] for r in subset])

    print("\n4. The same, by how lopsided the game is (DraftKings fair price of the favorite)")
    bands = [(label, low, high) for _key, label, low, high in BANDS]
    for label, low, high in bands:
        subset = [r for r in rows if low <= r["fav_dk_fair_pct"] < high]
        if not subset:
            continue
        print(f" favorite {label}")
        gap_summary("Polymarket - Kalshi", [r["gap_pm_kalshi"] for r in subset])
        gap_summary("Polymarket - DraftKings", [r["gap_pm_dk"] for r in subset])
        print(f"  {'DraftKings overround':<24} median={statistics.median([r['dk_overround_pts'] for r in subset]):5.2f} pts")

        favorite_gaps = [r["fav_gap_pm_dk"] for r in subset]
        print(
            f"  {'Polymarket - DK, favorite':<24} mean signed={statistics.fmean(favorite_gaps):+5.2f}  "
            f"Polymarket higher on the favorite in {sum(g > 0 for g in favorite_gaps)} of {len(subset)}"
        )
    favorite_gaps = [r["fav_gap_pm_dk"] for r in rows]
    print(
        f" all games: Polymarket minus DraftKings fair on the DraftKings favorite, mean signed={statistics.fmean(favorite_gaps):+5.2f}, "
        f"Polymarket higher in {sum(g > 0 for g in favorite_gaps)} of {len(rows)}"
    )

    print("\n5. What each venue charges to show the price")
    print(f"  DraftKings overround  median={statistics.median([r['dk_overround_pts'] for r in rows]):5.2f}  mean={statistics.fmean([r['dk_overround_pts'] for r in rows]):5.2f}  min={min(r['dk_overround_pts'] for r in rows):5.2f}  max={max(r['dk_overround_pts'] for r in rows):5.2f}  (points, both sides summed)")
    print(f"  Polymarket spread     median={statistics.median([r['pm_spread_c'] for r in rows]):5.2f}  mean={statistics.fmean([r['pm_spread_c'] for r in rows]):5.2f}  max={max(r['pm_spread_c'] for r in rows):5.2f}  (cents)")
    print(f"  Kalshi spread         median={statistics.median([r['kalshi_spread_c'] for r in rows]):5.2f}  mean={statistics.fmean([r['kalshi_spread_c'] for r in rows]):5.2f}  max={max(r['kalshi_spread_c'] for r in rows):5.2f}  (cents)")
    both = [r["pm_both_sides_taker_c"] for r in rows]
    print(f"  Polymarket, both sides bought at the ask plus the taker fee: median={statistics.median(both):5.2f}  mean={statistics.fmean(both):5.2f}  min={min(both):5.2f}  max={max(both):5.2f}  (cents over $1, the same unit as the overround)")
    print(f"  Polymarket costs less than the DraftKings overround on both sides in {sum(r['pm_both_sides_taker_c'] < r['dk_overround_pts'] for r in rows)} of {len(rows)} games")
    for label, low, high in bands:
        subset = [r for r in rows if low <= r["fav_dk_fair_pct"] < high]
        if subset:
            print(
                f"   favorite {label:<11} DK overround median={statistics.median([r['dk_overround_pts'] for r in subset]):5.2f}  "
                f"Polymarket spread plus taker fee median={statistics.median([r['pm_both_sides_taker_c'] for r in subset]):5.2f}"
            )
    for league in funnel:
        subset = [r for r in rows if r["league"] == league]
        if subset:
            print(
                f"   {LEAGUE_LABEL[league]:<18} DK overround median={statistics.median([r['dk_overround_pts'] for r in subset]):5.2f}  "
                f"PM spread median={statistics.median([r['pm_spread_c'] for r in subset]):5.2f}  Kalshi spread median={statistics.median([r['kalshi_spread_c'] for r in subset]):5.2f}"
            )

    print("\n6. Buying the favorite: cents per $1 of payout")
    dk_minus_pm = [r["fav_dk_price_c"] - r["fav_pm_all_in_c"] for r in rows]
    dk_minus_pm_ask = [r["fav_dk_price_c"] - r["fav_pm_ask_c"] for r in rows]
    dk_minus_kalshi = [r["fav_dk_price_c"] - r["fav_kalshi_ask_c"] for r in rows]
    print(f"  DraftKings price minus Polymarket ask                median={statistics.median(dk_minus_pm_ask):+5.2f}  mean={statistics.fmean(dk_minus_pm_ask):+5.2f}")
    print(f"  DraftKings price minus Polymarket ask plus taker fee median={statistics.median(dk_minus_pm):+5.2f}  mean={statistics.fmean(dk_minus_pm):+5.2f}  cheaper on Polymarket in {sum(d > 0 for d in dk_minus_pm)} of {len(rows)}")
    print(f"  DraftKings price minus Kalshi ask (no Kalshi fee)    median={statistics.median(dk_minus_kalshi):+5.2f}  mean={statistics.fmean(dk_minus_kalshi):+5.2f}")

    print(" the underdog")
    dog_pm_ask = [r["dog_dk_price_c"] - r["dog_pm_ask_c"] for r in rows]
    dog_pm = [r["dog_dk_price_c"] - r["dog_pm_all_in_c"] for r in rows]
    dog_kalshi = [r["dog_dk_price_c"] - r["dog_kalshi_ask_c"] for r in rows]
    print(f"  DraftKings price minus Polymarket ask                median={statistics.median(dog_pm_ask):+5.2f}  mean={statistics.fmean(dog_pm_ask):+5.2f}")
    print(f"  DraftKings price minus Polymarket ask plus taker fee median={statistics.median(dog_pm):+5.2f}  mean={statistics.fmean(dog_pm):+5.2f}  cheaper on Polymarket in {sum(d > 0 for d in dog_pm)} of {len(rows)}")
    print(f"  DraftKings price minus Kalshi ask (no Kalshi fee)    median={statistics.median(dog_kalshi):+5.2f}  mean={statistics.fmean(dog_kalshi):+5.2f}")
    print(" as a share of the stake, underdog and favorite")
    for label, dk_key, pm_key in (("favorite", "fav_dk_price_c", "fav_pm_all_in_c"), ("underdog", "dog_dk_price_c", "dog_pm_all_in_c")):
        shares = [100.0 * (r[dk_key] - r[pm_key]) / r[dk_key] for r in rows]
        print(f"  {label:<9} DraftKings price above Polymarket all-in by median={statistics.median(shares):+5.2f}%  mean={statistics.fmean(shares):+5.2f}% of the DraftKings price")

    print("\n7. Size on the two exchanges across the matched games")
    print(f"  Polymarket moneyline volume  ${sum(r['pm_volume_usd'] for r in rows):,.0f}  (median ${statistics.median([r['pm_volume_usd'] for r in rows]):,.0f} a game)")
    print(f"  Kalshi game volume           {sum(r['kalshi_volume_contracts'] for r in rows):,.0f} contracts  (median {statistics.median([r['kalshi_volume_contracts'] for r in rows]):,.0f} a game)")

    print("\n8. Every matched game (home-team probability, %)")
    print(f"  {'league':<5}{'game':<58}{'DK home/away':>14}{'DK fair':>9}{'Polymkt':>9}{'Kalshi':>8}{'PM-K':>7}{'PM-DK':>7}{'DK over':>9}")
    for row in sorted(rows, key=lambda r: (r["league"], r["start_utc"], r["game"])):
        print(
            f"  {row['league']:<5}{row['game'][:56]:<58}{row['dk_home'] + '/' + row['dk_away']:>14}{row['dk_fair_home_pct']:>9.2f}"
            f"{row['pm_home_pct']:>9.2f}{row['kalshi_home_pct']:>8.2f}{row['gap_pm_kalshi']:>+7.2f}{row['gap_pm_dk']:>+7.2f}{row['dk_overround_pts']:>9.2f}"
        )

    if args.ts:
        write_ts(args.ts, summarize(capture, rows, funnel))
        print(f"\nwrote {args.ts}", file=sys.stderr)

    if args.csv:
        with open(args.csv, "w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
            writer.writeheader()
            for row in sorted(rows, key=lambda r: (r["league"], r["start_utc"], r["game"])):
                writer.writerow({key: (f"{value:.4f}" if isinstance(value, float) else value) for key, value in row.items()})
        print(f"\nwrote {args.csv}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
