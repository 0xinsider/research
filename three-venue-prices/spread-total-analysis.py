#!/usr/bin/env python3
"""#14901. Polymarket's spread and total ladders against the DraftKings posted line.

Input is the JSON spread-total-capture.py writes. Every figure the
study at /research/polymarket-spreads-totals-vs-draftkings states comes from
this script's output.

The unit is the GAME, never the line. Polymarket lists a ladder of half-point
lines on each game and every line settles on the same final score, so a count of
lines would count one game many times (docs/research-articles/README.md, "Count
the unit that settles together").

A game enters a family (spread or total) when, at capture time:

  * ESPN lists it as scheduled with a start after the capture, and publishes a
    DraftKings line for the family with a number on both sides.
  * Polymarket lists at least one line of that family for the game that is
    accepting orders with a bid and an ask no more than MAX_BOOK_CENTS apart.

Definitions, all from the HOME team's side for spreads and the OVER for totals:

  ladder       each Polymarket line as (line, p), p the midpoint of bid and ask
               for "home covers this handicap" or "over this total".
               A market "Spread: Away (-2.5)" is the home team at +2.5, with
               p = 1 - the away midpoint.
  even line    the ladder line whose p is nearest 50 cents.
  busiest line the ladder line with the most volume traded.
  DraftKings   the posted line and the American price on each side. The fair
               probability divides each side's implied probability by the two
               sides' sum. Both sides sit near -110, so the proportional and
               equal-cents methods agree to a few hundredths of a point here.

Usage:
  python3 spread-total-analysis.py CAPTURE.json [--csv games.csv] [--ts data.ts]
"""

import argparse
import csv
import importlib.util
import json
import re
import statistics
import sys
from pathlib import Path

# Loading the sibling script below would otherwise leave a __pycache__ beside the evidence.
sys.dont_write_bytecode = True

_BASE = Path(__file__).resolve().parent / "analysis.py"
_spec = importlib.util.spec_from_file_location("three_venue_analysis", _BASE)
if _spec is None or _spec.loader is None:
    raise RuntimeError(f"cannot load {_BASE}")
base = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(base)

LEAGUE_LABEL = {"nfl": "NFL", "cfb": "College football", "mlb": "MLB"}
FAMILY_LABEL = {"spread": "Spread", "total": "Total"}
MAX_BOOK_CENTS = 5.0
# A ladder has an "even line" only when some tight line is priced near a coin flip.
EVEN_LOW, EVEN_HIGH = 0.40, 0.60
FEE = base.POLYMARKET_SPORTS_FEE


def parse_line(text) -> float | None:
    match = re.search(r"[-+]?\d+(?:\.\d+)?", str(text or ""))
    return float(match.group(0)) if match else None


def ladder_for(game: dict, markets: list[dict], family: str):
    """[{line, p, width_c, volume, slug}] for one game and family, from the home/over side."""
    home, away = game["home"], game["away"]
    start = base.parse_utc(game["date"])
    rows = []
    for market in markets:
        if market.get("sportsMarketType") != ("spreads" if family == "spread" else "totals"):
            continue
        if abs((base.parse_utc(market["gameStartTime"]) - start).total_seconds()) > 5400:
            continue
        outcomes = json.loads(market.get("outcomes") or "[]")
        bid, ask = base.to_float(market.get("bestBid")), base.to_float(market.get("bestAsk"))
        line = base.to_float(market.get("line"))
        if len(outcomes) != 2 or bid is None or ask is None or line is None or ask <= bid:
            continue
        if not market.get("acceptingOrders"):
            continue
        mid = (bid + ask) / 2.0
        if family == "spread":
            # The question names the team giving |line| points; outcome 0 is that team.
            giver_home = base.name_matches(outcomes[0], home) and base.name_matches(outcomes[1], away)
            giver_away = base.name_matches(outcomes[0], away) and base.name_matches(outcomes[1], home)
            if giver_home == giver_away:
                continue
            home_line = -abs(line) if giver_home else abs(line)
            p_home = mid if giver_home else 1.0 - mid
            rows.append({"line": home_line, "p": p_home})
        else:
            if [o.lower() for o in outcomes] != ["over", "under"]:
                continue
            # A total belongs to a game by start time and by both team names in the question.
            question = market.get("question") or ""
            teams = question.split(":")[0]
            parts = re.split(r"\s+vs\.?\s+", teams)
            if len(parts) != 2:
                continue
            forward = base.name_matches(parts[0], away) and base.name_matches(parts[1], home)
            backward = base.name_matches(parts[0], home) and base.name_matches(parts[1], away)
            if not (forward or backward):
                continue
            rows.append({"line": abs(line), "p": mid})
        width = (ask - bid) * 100.0
        rows[-1].update({"width_c": width, "tight": width <= MAX_BOOK_CENTS + 1e-9, "volume": base.to_float(market.get("volumeNum")) or 0.0, "slug": market["slug"]})
    unique = {}
    for row in rows:
        unique.setdefault(row["line"], row)
    return sorted(unique.values(), key=lambda r: r["line"])


def draftkings_line(game: dict, family: str):
    """(line, fair_p, overround_pts, side_a_odds, side_b_odds) from the home/over side, or None."""
    line = next((o for o in game.get("odds") or [] if o.get("provider") == "DraftKings"), None)
    if not line:
        return None
    if family == "spread":
        number = parse_line(line.get("spread_home_line"))
        a, b = line.get("spread_home_odds"), line.get("spread_away_odds")
    else:
        number = parse_line(line.get("total_over_line"))
        a, b = line.get("total_over_odds"), line.get("total_under_odds")
    pa, pb = base.american_to_implied(a), base.american_to_implied(b)
    if number is None or pa is None or pb is None:
        return None
    return (number, pa / (pa + pb), (pa + pb - 1.0) * 100.0, a, b)


def build_rows(capture: dict):
    started = base.parse_utc(capture["started_at"])
    rows, funnel = [], []
    for league, venues in capture["leagues"].items():
        games = venues["draftkings_via_espn"]["games"]
        markets = [m for m in venues["polymarket"]["markets"] if m.get("gameStartTime")]
        for family in ("spread", "total"):
            counts = {"league": league, "family": family, "scheduled": 0, "draftkings": 0, "polymarket": 0}
            for game in games:
                if not game.get("home") or not game.get("away") or game.get("status") != "STATUS_SCHEDULED":
                    continue
                if base.parse_utc(game["date"]) <= started:
                    continue
                counts["scheduled"] += 1
                posted = draftkings_line(game, family)
                if not posted:
                    continue
                counts["draftkings"] += 1
                listed = ladder_for(game, markets, family)
                ladder = [r for r in listed if r["tight"]]
                dk_line, dk_fair, dk_over, odds_a, odds_b = posted
                near_even = [r for r in ladder if EVEN_LOW <= r["p"] <= EVEN_HIGH]
                if not near_even:
                    continue
                counts["polymarket"] += 1
                even = min(near_even, key=lambda r: (abs(r["p"] - 0.5), abs(r["line"] - dk_line)))
                busiest = max(ladder, key=lambda r: (r["volume"], -abs(r["p"] - 0.5)))
                same = next((r for r in ladder if abs(r["line"] - dk_line) < 1e-9), None)
                # The ladder priced at the DraftKings number: read directly when Polymarket lists
                # the line, otherwise interpolated between the two lines around it.
                below = [r for r in ladder if r["line"] < dk_line]
                above = [r for r in ladder if r["line"] > dk_line]
                if same:
                    pm_at_dk = same["p"]
                elif below and above:
                    lo, hi = below[-1], above[0]
                    weight = (dk_line - lo["line"]) / (hi["line"] - lo["line"])
                    pm_at_dk = lo["p"] + (hi["p"] - lo["p"]) * weight
                else:
                    pm_at_dk = None
                ask = even["p"] + even["width_c"] / 200.0
                other_ask = (1.0 - even["p"]) + even["width_c"] / 200.0
                pm_both = (ask + FEE * ask * (1 - ask) + other_ask + FEE * other_ask * (1 - other_ask) - 1.0) * 100.0
                rows.append(
                    {
                        "league": league,
                        "family": family,
                        "game": game["name"],
                        "game_short": f"{game['away'].get('shortDisplayName') or game['away']['displayName']} at {game['home'].get('shortDisplayName') or game['home']['displayName']}",
                        "start_utc": base.parse_utc(game["date"]).strftime("%Y-%m-%dT%H:%MZ"),
                        "dk_line": dk_line,
                        "dk_odds": f"{odds_a}/{odds_b}",
                        "dk_fair_pct": dk_fair * 100.0,
                        "dk_overround_pts": dk_over,
                        "dk_whole_number": float(dk_line).is_integer(),
                        "pm_lines": len(ladder),
                        "pm_even_line": even["line"],
                        "pm_even_pct": even["p"] * 100.0,
                        "pm_even_width_c": even["width_c"],
                        "pm_busiest_line": busiest["line"],
                        "pm_busiest_volume": busiest["volume"],
                        "pm_ladder_volume": sum(r["volume"] for r in ladder),
                        "pm_lists_dk_line": same is not None,
                        "line_gap": even["line"] - dk_line,
                        "busiest_gap": busiest["line"] - dk_line,
                        "pm_at_dk_pct": None if pm_at_dk is None else pm_at_dk * 100.0,
                        "price_gap": None if pm_at_dk is None else (pm_at_dk - dk_fair) * 100.0,
                        "pm_both_sides_taker_c": pm_both,
                        "pm_listed_lines": len(listed),
                        "depth": [(min(3, int(round(abs(r["line"] - even["line"])))), r["width_c"], r["volume"]) for r in listed],
                    }
                )
            funnel.append(counts)
    return rows, funnel


def quantile(values, q):
    return base.quantile(values, q)


def family_stats(rows: list[dict]) -> dict:
    n = len(rows)
    line_gaps = [abs(r["line_gap"]) for r in rows]
    priced = [r for r in rows if r["price_gap"] is not None]
    price_gaps = [abs(r["price_gap"]) for r in priced]
    return {
        "n": n,
        "sameLineGames": sum(g < 1e-9 for g in line_gaps),
        "withinHalfGames": sum(g <= 0.5 + 1e-9 for g in line_gaps),
        "withinOneGames": sum(g <= 1.0 + 1e-9 for g in line_gaps),
        "lineGapMedian": statistics.median(line_gaps),
        "lineGapMean": statistics.fmean(line_gaps),
        "lineGapMax": max(line_gaps),
        "busiestSameLineGames": sum(abs(r["busiest_gap"]) < 1e-9 for r in rows),
        "busiestWithinHalfGames": sum(abs(r["busiest_gap"]) <= 0.5 + 1e-9 for r in rows),
        "wholeNumberGames": sum(r["dk_whole_number"] for r in rows),
        "listsDkLineGames": sum(r["pm_lists_dk_line"] for r in rows),
        "pricedGames": len(priced),
        "priceGapMedian": statistics.median(price_gaps) if price_gaps else 0.0,
        "priceGapMean": statistics.fmean(price_gaps) if price_gaps else 0.0,
        "priceGapP90": quantile(price_gaps, 0.9) if price_gaps else 0.0,
        "priceGapMax": max(price_gaps) if price_gaps else 0.0,
        "priceWithin2Pct": 100.0 * sum(g <= 2.0 for g in price_gaps) / len(price_gaps) if price_gaps else 0.0,
        "priceWithin3Pct": 100.0 * sum(g <= 3.0 for g in price_gaps) / len(price_gaps) if price_gaps else 0.0,
        "dkOverroundMedian": statistics.median([r["dk_overround_pts"] for r in rows]),
        "pmBothSidesTakerMedian": statistics.median([r["pm_both_sides_taker_c"] for r in rows]),
        "pmCheaperGames": sum(r["pm_both_sides_taker_c"] < r["dk_overround_pts"] for r in rows),
        "pmEvenWidthMedian": statistics.median([r["pm_even_width_c"] for r in rows]),
        "pmLinesMedian": statistics.median([r["pm_lines"] for r in rows]),
        "pmLadderVolume": sum(r["pm_ladder_volume"] for r in rows),
    }


DEPTH_LABEL = {0: "The even line", 1: "1 point away", 2: "2 points away", 3: "3 or more away"}


def depth_by_step(rows: list[dict]) -> list[dict]:
    """How the book thins away from the even line. Reads every quoted line, tight or not."""
    total_volume = sum(volume for row in rows for _step, _width, volume in row["depth"]) or 1.0
    out = []
    for step in (0, 1, 2, 3):
        values = [(width, volume) for row in rows for s_, width, volume in row["depth"] if s_ == step]
        if not values:
            continue
        out.append(
            {
                "key": str(step),
                "label": DEPTH_LABEL[step],
                "lines": len(values),
                "widthMedian": statistics.median([w for w, _ in values]),
                "tightPct": 100.0 * sum(w <= MAX_BOOK_CENTS + 1e-9 for w, _ in values) / len(values),
                "tradedPct": 100.0 * sum(v > 0 for _, v in values) / len(values),
                "volumeSharePct": 100.0 * sum(v for _, v in values) / total_volume,
            }
        )
    return out


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("capture")
    parser.add_argument("--csv")
    parser.add_argument("--ts")
    args = parser.parse_args()
    with open(args.capture, encoding="utf-8") as handle:
        capture = json.load(handle)
    rows, funnel = build_rows(capture)
    print(f"capture {capture['started_at']} to {capture['finished_at']}")

    print("\n1. Funnel (games)")
    print(f"  {'league':<18}{'family':<8}{'scheduled':>10}{'DK line':>9}{'+Polymarket':>13}")
    for counts in funnel:
        print(f"  {LEAGUE_LABEL[counts['league']]:<18}{FAMILY_LABEL[counts['family']]:<8}{counts['scheduled']:>10}{counts['draftkings']:>9}{counts['polymarket']:>13}")

    summary = {"capturedAt": capture["started_at"], "finishedAt": capture["finished_at"], "funnel": funnel, "families": {}, "byLeague": [], "games": []}
    for family in ("spread", "total"):
        subset = [r for r in rows if r["family"] == family]
        if not subset:
            continue
        stats = family_stats(subset)
        summary["families"][family] = stats
        print(f"\n2. {FAMILY_LABEL[family]}: Polymarket's even line against the DraftKings line, {stats['n']} games")
        print(f"  same number              {stats['sameLineGames']:>3} of {stats['n']}")
        print(f"  within half a point      {stats['withinHalfGames']:>3} of {stats['n']}")
        print(f"  within one point         {stats['withinOneGames']:>3} of {stats['n']}")
        print(f"  gap in points            median={stats['lineGapMedian']:.2f}  mean={stats['lineGapMean']:.2f}  max={stats['lineGapMax']:.2f}")
        print(f"  DraftKings on a whole number {stats['wholeNumberGames']} of {stats['n']} (Polymarket lists half-point lines only); Polymarket lists the DraftKings number in {stats['listsDkLineGames']}")
        print(f"  busiest Polymarket line  same as DraftKings in {stats['busiestSameLineGames']}, within half a point in {stats['busiestWithinHalfGames']}")
        print(f"  price at the DraftKings number, Polymarket minus DraftKings fair, {stats['pricedGames']} games: median|gap|={stats['priceGapMedian']:.2f}  mean={stats['priceGapMean']:.2f}  p90={stats['priceGapP90']:.2f}  max={stats['priceGapMax']:.2f}  within2={stats['priceWithin2Pct']:.1f}%  within3={stats['priceWithin3Pct']:.1f}%")
        print(f"  cost of both sides       DraftKings overround median={stats['dkOverroundMedian']:.2f}  Polymarket even line, ask plus taker fee median={stats['pmBothSidesTakerMedian']:.2f}  Polymarket cheaper in {stats['pmCheaperGames']} of {stats['n']}")
        print(f"  Polymarket ladder        median {stats['pmLinesMedian']:.0f} tight lines a game, even-line book {stats['pmEvenWidthMedian']:.2f}c wide, ${stats['pmLadderVolume']:,.0f} traded")
        for league in capture["leagues"]:
            league_rows = [r for r in subset if r["league"] == league]
            if not league_rows:
                continue
            league_stats = family_stats(league_rows)
            summary["byLeague"].append({"key": f"{league}-{family}", "league": league, "leagueLabel": LEAGUE_LABEL[league], "family": family, **league_stats})
            print(f"   {LEAGUE_LABEL[league]:<18} n={league_stats['n']:>3}  same={league_stats['sameLineGames']:>3}  within half={league_stats['withinHalfGames']:>3}  line gap mean={league_stats['lineGapMean']:.2f}  price gap median={league_stats['priceGapMedian']:.2f}  DK overround={league_stats['dkOverroundMedian']:.2f}  PM both sides={league_stats['pmBothSidesTakerMedian']:.2f}")

    print("\n3. How the Polymarket book thins away from the even line (every quoted line)")
    summary["depth"] = {}
    for key, label, subset in (("all", "All leagues", rows), ("nfl", "NFL", [r for r in rows if r["league"] == "nfl"])):
        summary["depth"][key] = depth_by_step(subset)
        print(f" {label}")
        for bucket in summary["depth"][key]:
            print(f"  {bucket['label']:<18} lines={bucket['lines']:>4}  median width={bucket['widthMedian']:6.2f}c  5c or tighter={bucket['tightPct']:5.1f}%  traded={bucket['tradedPct']:5.1f}%  share of volume={bucket['volumeSharePct']:5.1f}%")

    print("\n4. Every game")
    print(f"  {'lg':<4}{'fam':<7}{'game':<40}{'DK line':>8}{'DK odds':>11}{'DK fair':>8}{'PM even':>8}{'PM busy':>8}{'PM@DK':>7}{'gap':>7}{'lines':>6}")
    for row in sorted(rows, key=lambda r: (r["family"], r["league"], r["start_utc"], r["game"])):
        at_dk = "" if row["pm_at_dk_pct"] is None else f"{row['pm_at_dk_pct']:.1f}"
        gap = "" if row["price_gap"] is None else f"{row['price_gap']:+.2f}"
        print(f"  {row['league']:<4}{row['family']:<7}{row['game_short'][:38]:<40}{row['dk_line']:>8.1f}{row['dk_odds']:>11}{row['dk_fair_pct']:>8.1f}{row['pm_even_line']:>8.1f}{row['pm_busiest_line']:>8.1f}{at_dk:>7}{gap:>7}{row['pm_lines']:>6}")
        summary["games"].append(
            {
                "league": row["league"],
                "family": row["family"],
                "game": row["game"],
                "gameShort": row["game_short"],
                "dkLine": row["dk_line"],
                "dkOdds": row["dk_odds"],
                "dkFairPct": row["dk_fair_pct"],
                "pmEvenLine": row["pm_even_line"],
                "pmEvenPct": row["pm_even_pct"],
                "pmBusiestLine": row["pm_busiest_line"],
                "pmAtDkPct": row["pm_at_dk_pct"],
                "priceGap": row["price_gap"],
                "pmLines": row["pm_lines"],
            }
        )

    if args.ts:
        body = json.dumps(base.rounded(summary), indent=2)
        with open(args.ts, "w", encoding="utf-8") as handle:
            handle.write(
                "// GENERATED FILE -- DO NOT EDIT BY HAND.\n"
                "//\n"
                "// #14901. Every aggregate and every game behind\n"
                "// /research/polymarket-spreads-totals-vs-draftkings, to four decimal places.\n"
                "//\n"
                "// Regenerate, from the repository root:\n"
                "//   V=docs/research-articles/verification\n"
                "//   python3 $V/spread-total-analysis.py $V/spread-total-capture.json \\\n"
                "//     --ts web/src/lib/research-evidence/spread-total-lines.data.ts\n"
                "// A clean `git diff` after that command is the check that this file matches the capture.\n"
                "\n"
                f"export const SPREAD_TOTAL_DATA = {body};\n"
            )
        print(f"\nwrote {args.ts}", file=sys.stderr)
    if args.csv:
        fields = [k for k in rows[0].keys() if k != "depth"]
        with open(args.csv, "w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=fields)
            writer.writeheader()
            for row in sorted(rows, key=lambda r: (r["family"], r["league"], r["start_utc"], r["game"])):
                writer.writerow({k: (f"{row[k]:.4f}" if isinstance(row[k], float) else row[k]) for k in fields})
        print(f"wrote {args.csv}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
