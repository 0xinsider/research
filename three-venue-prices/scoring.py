#!/usr/bin/env python3
"""#14900. Which price was right: score the #14883 three-venue capture.

Joins two committed files and nothing else:

  games.csv     81 games, three home-win probabilities each,
                                       captured 16:01 UTC 2026-09-18, before any of
                                       them kicked off.
  results.csv   the final of every one of those 81 games,
                                       read from ESPN's scoreboard by the event id
                                       the capture recorded.

The sample is the capture's. This script refuses to run if the two files do not
hold the same 81 games, because the study's one design guarantee is that no game
was added or dropped once the results were known.

Scores, all on the HOME team's probability:

  Brier     mean of (p - y)^2, y = 1 when the home team won. Lower is better.
  log loss  mean of -(y ln p + (1 - y) ln(1 - p)), in nats. Lower is better.
            No clipping is applied or needed; the extreme captured price is far
            from 0 and 1, and the script asserts that.

Every pairwise difference carries a game-resampled interval: the 81 games are
resampled with replacement B times, the difference in mean score is recomputed
on each resample, and the reported interval is the 2.5th to 97.5th percentile of
those means. It is an interval on the difference between two venues on THESE
games, not on prediction-market skill in general.

Usage, from this directory:
  python3 scoring.py --games games.csv --results results.csv > scoring-output.txt

The --ts flag writes the site's generated evidence module and is used only in
the site repository; it changes nothing this report prints.
"""

import argparse
import csv
import json
import math
import random
import statistics
import sys

VENUES = [
    ("pm", "Polymarket", "pm_home_pct"),
    ("kalshi", "Kalshi", "kalshi_home_pct"),
    ("dk", "DraftKings", "dk_fair_home_pct"),
    ("dkEqual", "DraftKings (equal cents)", "dk_equal_home_pct"),
]

# The four venues the page scores head to head. The equal-cents DraftKings price
# is carried as a robustness read only: it is the same line with the margin
# removed a different way, so it is not a fourth opinion.
HEADLINE = ["pm", "kalshi", "dk"]

PAIRS = [
    ("pm", "dk"),
    ("kalshi", "dk"),
    ("pm", "kalshi"),
    ("pm", "dkEqual"),
]

# The parent study's bands, on the favorite's price at the venue being scored.
BANDS = [
    ("50to60", "50 to 60%", 50.0, 60.0),
    ("60to75", "60 to 75%", 60.0, 75.0),
    ("75to90", "75 to 90%", 75.0, 90.0),
    ("90up", "90% and up", 90.0, 100.1),
]

RESAMPLES = 20000
SEED = 14900


def brier(p: float, y: float) -> float:
    return (p - y) ** 2


def log_loss(p: float, y: float) -> float:
    return -(y * math.log(p) + (1.0 - y) * math.log(1.0 - p))


def load(games_path: str, results_path: str) -> list[dict]:
    games = list(csv.DictReader(open(games_path, encoding="utf-8")))
    results = {
        (row["league"], row["game"]): row
        for row in csv.DictReader(open(results_path, encoding="utf-8"))
    }
    if len(results) != len(games):
        raise SystemExit(
            f"the results file holds {len(results)} games and the capture holds {len(games)}; "
            "the sample is fixed by the capture"
        )
    rows = []
    for game in games:
        key = (game["league"], game["game"])
        result = results.get(key)
        if result is None:
            raise SystemExit(f"no result for the captured game {key}")
        if result["status"] != "STATUS_FINAL":
            raise SystemExit(f"{key} is {result['status']}, not final")
        if result["home_result"] not in ("0", "1"):
            raise SystemExit(f"{key} ended {result['home_result']}; a tie needs a stated rule")
        row = dict(game)
        for field in ("espn_event_id", "home_score", "away_score", "read_at"):
            row[field] = result[field]
        row["home_win"] = float(result["home_result"])
        for _key, _label, field in VENUES:
            probability = float(game[field]) / 100.0
            if not 0.0 < probability < 1.0:
                raise SystemExit(f"{key} has {field}={game[field]}, outside (0, 100)")
            row[field] = probability
        for field in (
            "gap_pm_dk",
            "gap_kalshi_dk",
            "gap_pm_kalshi",
            "gap_pm_dk_equal",
            "fav_dk_fair_pct",
            "pm_volume_usd",
        ):
            row[field] = float(game[field])
        rows.append(row)
    return rows


def per_game(rows: list[dict], venue_key: str) -> tuple[list[float], list[float]]:
    field = next(field for key, _label, field in VENUES if key == venue_key)
    briers = [brier(row[field], row["home_win"]) for row in rows]
    losses = [log_loss(row[field], row["home_win"]) for row in rows]
    return briers, losses


def resampled_interval(diffs: list[float], rng: random.Random) -> dict:
    """Percentile interval on the mean of a per-game difference, games resampled."""
    n = len(diffs)
    means = []
    for _ in range(RESAMPLES):
        total = 0.0
        for _draw in range(n):
            total += diffs[rng.randrange(n)]
        means.append(total / n)
    means.sort()
    lo = means[int(0.025 * RESAMPLES)]
    hi = means[int(0.975 * RESAMPLES) - 1]
    mean = statistics.fmean(diffs)
    share_negative = sum(1 for value in means if value < 0) / RESAMPLES
    # What 81 games can and cannot separate. The interval's half-width shrinks
    # with the square root of the sample, so holding the per-game spread fixed,
    # this is the number of games at which the half-width would fall to the
    # difference actually observed -- the point where a gap this size would stop
    # spanning zero. It is an order of magnitude, not a power calculation.
    half_width = (hi - lo) / 2.0
    games_needed = (
        math.ceil(n * (half_width / abs(mean)) ** 2) if abs(mean) > 0 else None
    )
    return {
        "mean": mean,
        "lo": lo,
        "hi": hi,
        "shareBelowZero": 100.0 * share_negative,
        "halfWidth": half_width,
        "gamesToSeparate": games_needed,
    }


def favorite_bands(rows: list[dict], venue_key: str) -> list[dict]:
    field = next(field for key, _label, field in VENUES if key == venue_key)
    out = []
    for key, label, low, high in BANDS:
        band = []
        for row in rows:
            probability = row[field]
            favorite_pct = 100.0 * max(probability, 1.0 - probability)
            if low <= favorite_pct < high:
                favorite_won = (row["home_win"] == 1.0) == (probability >= 0.5)
                band.append((favorite_pct, favorite_won))
        if not band:
            out.append(
                {
                    "key": key,
                    "label": label,
                    "n": 0,
                    "meanPct": 0.0,
                    "wins": 0,
                    "wonPct": 0.0,
                    "wonMinusPricePts": 0.0,
                    "sePts": 0.0,
                    "standardErrors": 0.0,
                }
            )
            continue
        wins = sum(1 for _pct, won in band if won)
        mean_pct = statistics.fmean([pct for pct, _won in band])
        won_pct = 100.0 * wins / len(band)
        # The binomial standard error at the band's own price, in points, so the
        # gap between what the price said and what happened can be read against
        # what a band this size can resolve.
        share = mean_pct / 100.0
        se_pct = 100.0 * math.sqrt(share * (1.0 - share) / len(band))
        out.append(
            {
                "key": key,
                "label": label,
                "n": len(band),
                "meanPct": mean_pct,
                "wins": wins,
                "wonPct": won_pct,
                "wonMinusPricePts": won_pct - mean_pct,
                "sePts": se_pct,
                "standardErrors": (won_pct - mean_pct) / se_pct if se_pct > 0 else 0.0,
            }
        )
    return out


def disagreement(rows: list[dict], exchange_key: str, gap_field: str, top: int) -> dict:
    """The games where DraftKings' fair price sat furthest from the exchange.

    `gap_field` is the exchange price minus the DraftKings fair price, in points,
    as the capture's analysis wrote it. A positive gap is the exchange leaning
    toward the home team relative to DraftKings.
    """
    ranked = sorted(rows, key=lambda row: -abs(row[gap_field]))
    subset = ranked[:top]
    exchange_field = next(field for key, _label, field in VENUES if key == exchange_key)
    dk_field = "dk_fair_home_pct"
    lean_right = 0
    lean_to_favorite = 0
    lean_to_favorite_right = 0
    lean_to_dog = 0
    lean_to_dog_right = 0
    for row in subset:
        leaned_home = row[gap_field] > 0
        home_won = row["home_win"] == 1.0
        correct = leaned_home == home_won
        lean_right += correct
        # The confound this splits out: removing the DraftKings margin
        # proportionally leaves the exchange above DraftKings on the favorite in
        # most games, and favorites won most games. A lean toward the favorite is
        # therefore right by construction more often than a lean away from it.
        home_is_favorite = row[dk_field] >= 0.5
        if leaned_home == home_is_favorite:
            lean_to_favorite += 1
            lean_to_favorite_right += correct
        else:
            lean_to_dog += 1
            lean_to_dog_right += correct
    exchange_brier = statistics.fmean([brier(row[exchange_field], row["home_win"]) for row in subset])
    dk_brier = statistics.fmean([brier(row[dk_field], row["home_win"]) for row in subset])
    exchange_loss = statistics.fmean([log_loss(row[exchange_field], row["home_win"]) for row in subset])
    dk_loss = statistics.fmean([log_loss(row[dk_field], row["home_win"]) for row in subset])
    return {
        "n": len(subset),
        "minGap": min(abs(row[gap_field]) for row in subset),
        "maxGap": max(abs(row[gap_field]) for row in subset),
        "leanRight": lean_right,
        "leanToFavorite": lean_to_favorite,
        "leanToFavoriteRight": lean_to_favorite_right,
        "leanToUnderdog": lean_to_dog,
        "leanToUnderdogRight": lean_to_dog_right,
        "exchangeBrier": exchange_brier,
        "dkBrier": dk_brier,
        "exchangeLogLoss": exchange_loss,
        "dkLogLoss": dk_loss,
    }


def write_ts(path: str, payload: dict) -> None:
    header = """// GENERATED FILE -- DO NOT EDIT BY HAND.
//
// #14900. Every figure in the "Which price was right" addendum on
// /research/use-0xinsider-for-kalshi-draftkings, scored against the finals of
// the same 81 games the #14883 capture priced before any of them kicked off.
//
// Regenerate, from the repository root:
//   V=docs/research-articles/verification
//   python3 $V/2026-09-23-three-venue-scoring.py \\
//     --games $V/2026-09-18-three-venue-games.csv \\
//     --results $V/2026-09-23-three-venue-results.csv \\
//     --ts web/src/lib/research-evidence/three-venue-scoring.data.ts \\
//     > $V/2026-09-23-three-venue-scoring-output.txt
// A clean `git diff` after that command is the check that this file matches the
// capture and the finals.

export const THREE_VENUE_SCORING_DATA = """
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(header)
        handle.write(json.dumps(payload, indent=2))
        handle.write(";\n")


def round_deep(value, places: int = 6):
    if isinstance(value, float):
        return round(value, places)
    if isinstance(value, dict):
        return {key: round_deep(item, places) for key, item in value.items()}
    if isinstance(value, list):
        return [round_deep(item, places) for item in value]
    return value


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--games", required=True)
    parser.add_argument("--results", required=True)
    parser.add_argument("--ts", help="write the generated evidence module here")
    args = parser.parse_args()

    rows = load(args.games, args.results)
    rng = random.Random(SEED)
    n = len(rows)
    home_wins = int(sum(row["home_win"] for row in rows))

    print(f"#14900. Scoring the {n} games captured at 16:01:03 UTC on 2026-09-18.")
    read_at = rows[0]["read_at"]
    print(f"Finals from ESPN's scoreboard, read at {read_at} by the capture's own event ids.")
    print(f"Games {n}, home wins {home_wins}, away wins {n - home_wins}, ties 0.")
    print(f"Game-resampled intervals: {RESAMPLES:,} resamples, seed {SEED}, 2.5th to 97.5th percentile.")

    print("\n1. Score per venue, home-team probability")
    print(f"  {'venue':<26}{'n':>4}{'mean p':>9}{'Brier':>9}{'log loss':>10}")
    scores = {}
    venue_rows = []
    for key, label, field in VENUES:
        briers, losses = per_game(rows, key)
        scores[key] = (briers, losses)
        mean_p = 100.0 * statistics.fmean([row[field] for row in rows])
        print(
            f"  {label:<26}{n:>4}{mean_p:>8.2f}%{statistics.fmean(briers):>9.4f}{statistics.fmean(losses):>10.4f}"
        )
        venue_rows.append(
            {
                "key": key,
                "label": label,
                "n": n,
                "meanHomePct": mean_p,
                "brier": statistics.fmean(briers),
                "logLoss": statistics.fmean(losses),
            }
        )
    base_rate = home_wins / n
    always_base = statistics.fmean([brier(base_rate, row["home_win"]) for row in rows])
    always_base_loss = statistics.fmean([log_loss(base_rate, row["home_win"]) for row in rows])
    print(f"  {'(the home rate, ' + f'{100 * base_rate:.1f}%, every game)':<26}{n:>4}{100 * base_rate:>8.2f}%{always_base:>9.4f}{always_base_loss:>10.4f}")
    print(f"  {'(a coin, 50% every game)':<26}{n:>4}{50.0:>8.2f}%{0.25:>9.4f}{math.log(2):>10.4f}")

    print("\n2. Pairwise difference, A minus B, per game, with a game-resampled interval")
    print("  a negative difference means A scored better; the interval is on these 81 games only")
    pair_rows = []
    for a, b in PAIRS:
        label_a = next(label for key, label, _f in VENUES if key == a)
        label_b = next(label for key, label, _f in VENUES if key == b)
        brier_diffs = [x - y for x, y in zip(scores[a][0], scores[b][0])]
        loss_diffs = [x - y for x, y in zip(scores[a][1], scores[b][1])]
        brier_ci = resampled_interval(brier_diffs, rng)
        loss_ci = resampled_interval(loss_diffs, rng)
        print(f"  {label_a} minus {label_b}")
        print(
            f"    Brier    {brier_ci['mean']:+9.5f}  [{brier_ci['lo']:+.5f}, {brier_ci['hi']:+.5f}]"
            f"  A better in {brier_ci['shareBelowZero']:5.1f}% of resamples"
        )
        print(
            f"    log loss {loss_ci['mean']:+9.5f}  [{loss_ci['lo']:+.5f}, {loss_ci['hi']:+.5f}]"
            f"  A better in {loss_ci['shareBelowZero']:5.1f}% of resamples"
        )
        print(
            f"    a gap this size stops spanning zero at about {brier_ci['gamesToSeparate']:,} games"
            f" on Brier and {loss_ci['gamesToSeparate']:,} on log loss, at this per-game spread"
        )
        pair_rows.append(
            {
                "key": f"{a}_{b}",
                "labelA": label_a,
                "labelB": label_b,
                "brier": brier_ci,
                "logLoss": loss_ci,
            }
        )

    print("\n3. The favorite's record, banded by the favorite's price at that venue")
    band_rows = []
    for key in HEADLINE:
        label = next(label for k, label, _f in VENUES if k == key)
        print(f" {label}")
        print(
            f"  {'band':<12}{'n':>4}{'mean fav price':>16}{'favorites won':>15}{'actual':>9}"
            f"{'vs price':>10}{'std errs':>10}"
        )
        bands = favorite_bands(rows, key)
        for band in bands:
            if band["n"] == 0:
                continue
            print(
                f"  {band['label']:<12}{band['n']:>4}{band['meanPct']:>15.2f}%"
                f"{str(band['wins']) + ' of ' + str(band['n']):>15}{band['wonPct']:>8.1f}%"
                f"{band['wonMinusPricePts']:>+10.1f}{band['standardErrors']:>+10.2f}"
            )
        band_rows.append({"key": key, "label": label, "bands": bands})
    all_favorites = sum(band["wins"] for band in favorite_bands(rows, "dk"))
    print(f"  DraftKings favorites won {all_favorites} of {n} ({100.0 * all_favorites / n:.1f}%)")

    print("\n4. The games where DraftKings and the exchanges disagreed most")
    print("  the exchange price minus the DraftKings fair price, largest absolute gaps first")
    disagreements = []
    for top in (10, 20, 27):
        row = disagreement(rows, "pm", "gap_pm_dk", top)
        print(
            f"  top {top:>2} by |Polymarket - DraftKings|  gap {row['minGap']:.2f} to {row['maxGap']:.2f} pts"
            f"  Polymarket's lean was the winning side in {row['leanRight']} of {row['n']}"
        )
        print(
            f"      Brier    Polymarket {row['exchangeBrier']:.4f}  DraftKings {row['dkBrier']:.4f}"
            f"  ({row['exchangeBrier'] - row['dkBrier']:+.4f})"
        )
        print(
            f"      log loss Polymarket {row['exchangeLogLoss']:.4f}  DraftKings {row['dkLogLoss']:.4f}"
            f"  ({row['exchangeLogLoss'] - row['dkLogLoss']:+.4f})"
        )
        print(
            f"      of those, the lean was toward the DraftKings favorite in {row['leanToFavorite']}"
            f" (right {row['leanToFavoriteRight']}) and toward the underdog in {row['leanToUnderdog']}"
            f" (right {row['leanToUnderdogRight']})"
        )
        disagreements.append({"top": top, **row})
    kalshi_top20 = disagreement(rows, "kalshi", "gap_kalshi_dk", 20)
    print(
        f"  top 20 by |Kalshi - DraftKings|          gap {kalshi_top20['minGap']:.2f} to {kalshi_top20['maxGap']:.2f} pts"
        f"  Kalshi's lean was the winning side in {kalshi_top20['leanRight']} of {kalshi_top20['n']}"
    )
    print(
        f"      Brier    Kalshi {kalshi_top20['exchangeBrier']:.4f}  DraftKings {kalshi_top20['dkBrier']:.4f}"
        f"  ({kalshi_top20['exchangeBrier'] - kalshi_top20['dkBrier']:+.4f})"
    )

    lean_all = sum(1 for row in rows if (row["gap_pm_dk"] > 0) == (row["home_win"] == 1.0))
    decided = sum(1 for row in rows if row["gap_pm_dk"] != 0.0)
    lean_to_favorite_all = sum(
        1 for row in rows if (row["gap_pm_dk"] > 0) == (row["dk_fair_home_pct"] >= 0.5)
    )
    print(
        f"  across all {n} games, Polymarket's lean away from DraftKings named the winning side "
        f"in {lean_all} of {decided} with a gap"
    )
    print(
        f"  the confound: that lean pointed at the DraftKings favorite in {lean_to_favorite_all} of {n} games,"
        f" and DraftKings favorites won {all_favorites} of {n}, so a lean toward the favorite is right"
        f" more often than not before any venue shows skill"
    )

    print("\n4b. The same disagreement read against the equal-cents DraftKings price")
    print("  removing the DraftKings margin as equal cents instead of proportionally takes most")
    print("  of the favorite-side tilt out of the gap, so the lean is closer to a free direction")
    equal_disagreements = []
    for top in (10, 20, 27):
        row = disagreement(rows, "pm", "gap_pm_dk_equal", top)
        print(
            f"  top {top:>2} by |Polymarket - DraftKings equal cents|  gap {row['minGap']:.2f}"
            f" to {row['maxGap']:.2f} pts  Polymarket's lean was the winning side in"
            f" {row['leanRight']} of {row['n']}"
        )
        print(
            f"      toward the favorite in {row['leanToFavorite']} (right {row['leanToFavoriteRight']}),"
            f" toward the underdog in {row['leanToUnderdog']} (right {row['leanToUnderdogRight']})"
        )
        equal_disagreements.append({"top": top, **row})
    lean_equal_all = sum(
        1 for row in rows if (row["gap_pm_dk_equal"] > 0) == (row["home_win"] == 1.0)
    )
    lean_equal_favorite = sum(
        1 for row in rows if (row["gap_pm_dk_equal"] > 0) == (row["dk_fair_home_pct"] >= 0.5)
    )
    print(
        f"  across all {n} games, that lean named the winning side in {lean_equal_all} of {n},"
        f" and pointed at the favorite in {lean_equal_favorite} of {n}"
    )

    print("\n5. The one game the three venues did not agree on a favorite")
    split = [
        row
        for row in rows
        if (row["pm_home_pct"] >= 0.5) != (row["dk_fair_home_pct"] >= 0.5)
        or (row["pm_home_pct"] >= 0.5) != (row["kalshi_home_pct"] >= 0.5)
    ]
    split_rows = []
    for row in split:
        print(
            f"  {row['league']} {row['game']}  DK {100 * row['dk_fair_home_pct']:.2f}%"
            f"  Polymarket {100 * row['pm_home_pct']:.2f}%  Kalshi {100 * row['kalshi_home_pct']:.2f}%"
            f"  final {row['home_score']}-{row['away_score']}, home {'won' if row['home_win'] else 'lost'}"
        )
        split_rows.append(
            {
                "league": row["league"],
                "game": row["game"],
                "gameShort": row["game_short"],
                "dkFairHomePct": 100 * row["dk_fair_home_pct"],
                "pmHomePct": 100 * row["pm_home_pct"],
                "kalshiHomePct": 100 * row["kalshi_home_pct"],
                "homeScore": int(row["home_score"]),
                "awayScore": int(row["away_score"]),
                "homeWon": row["home_win"] == 1.0,
            }
        )

    print("\n6. Score by league")
    league_rows = []
    for league, label in (("cfb", "College football"), ("mlb", "MLB"), ("nfl", "NFL"), ("wnba", "WNBA")):
        subset = [row for row in rows if row["league"] == league]
        if not subset:
            continue
        entry = {"key": league, "label": label, "n": len(subset), "venues": []}
        print(f" {label}  n={len(subset)}")
        for key in HEADLINE:
            field = next(field for k, _label, field in VENUES if k == key)
            venue_label = next(venue_label for k, venue_label, _f in VENUES if k == key)
            b = statistics.fmean([brier(row[field], row["home_win"]) for row in subset])
            l = statistics.fmean([log_loss(row[field], row["home_win"]) for row in subset])
            print(f"  {venue_label:<14}Brier {b:.4f}  log loss {l:.4f}")
            entry["venues"].append({"key": key, "label": venue_label, "brier": b, "logLoss": l})
        league_rows.append(entry)

    print("\n7. Every game, scored")
    print(
        f"  {'league':<5}{'game':<46}{'final':>9}{'home':>6}"
        f"{'DK':>8}{'PM':>8}{'Kalshi':>8}{'B(DK)':>8}{'B(PM)':>8}{'B(K)':>8}"
    )
    for row in sorted(rows, key=lambda r: (r["league"], r["start_utc"], r["game"])):
        print(
            f"  {row['league']:<5}{row['game'][:44]:<46}"
            f"{row['home_score'] + '-' + row['away_score']:>9}{('won' if row['home_win'] else 'lost'):>6}"
            f"{100 * row['dk_fair_home_pct']:>8.2f}{100 * row['pm_home_pct']:>8.2f}{100 * row['kalshi_home_pct']:>8.2f}"
            f"{brier(row['dk_fair_home_pct'], row['home_win']):>8.4f}"
            f"{brier(row['pm_home_pct'], row['home_win']):>8.4f}"
            f"{brier(row['kalshi_home_pct'], row['home_win']):>8.4f}"
        )

    if args.ts:
        payload = {
            "resultsReadAt": read_at,
            "gamesN": n,
            "homeWins": home_wins,
            "awayWins": n - home_wins,
            "ties": 0,
            "resamples": RESAMPLES,
            "seed": SEED,
            "venues": venue_rows,
            "baseline": {
                "homeRatePct": 100.0 * base_rate,
                "brier": always_base,
                "logLoss": always_base_loss,
                "coinBrier": 0.25,
                "coinLogLoss": math.log(2),
            },
            "pairs": pair_rows,
            "byVenueBands": band_rows,
            "dkFavoriteWins": all_favorites,
            "disagreements": disagreements,
            "kalshiDisagreementTop20": {"top": 20, **kalshi_top20},
            "leanCorrectAll": lean_all,
            "leanDecidedAll": decided,
            "leanToFavoriteAll": lean_to_favorite_all,
            "equalCentsDisagreements": equal_disagreements,
            "leanCorrectAllEqualCents": lean_equal_all,
            "leanToFavoriteAllEqualCents": lean_equal_favorite,
            "splitFavoriteGames": split_rows,
            "byLeague": league_rows,
        }
        write_ts(args.ts, round_deep(payload))
        print(f"\nwrote {args.ts}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
