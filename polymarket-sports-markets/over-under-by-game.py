"""How often Polymarket game totals settled Under, counted by game (#13926).

Reads over-under-by-game.csv, one row per game, written by query 3 of
over-under-by-game.sql. Prints three measures for every sport with 150 or more games, and all
sports together:

  every line   the share of all settled total lines that went Under, the measure the first run published. Its
               interval resamples games, because every line on a game settles on the same final score. The
               binomial half-width the first run printed is shown beside it for comparison.
  main line    each game's most-traded total line by Polymarket's reported lifetime volume, one per game. Games
               with no reported volume on any line are left out of this measure.
  middle rung  each game's median line by line value, the two middle lines at half weight when the count is even.

It then re-runs the first run's buy-level bootstrap with games as the cluster: over-under-game-edge.csv
(query 4) sums each group's buys and edge by game.

Intervals: 95% percentile bootstrap, 5,000 draws resampling games, seed 20260913.

Usage: python3 over-under-by-game.py
"""

import csv
import math
from collections import defaultdict

import numpy as np

DRAWS = 5_000
SEED = 20260913
MIN_GAMES = 150
LABELS = {"Basketball": "Other basketball"}

rows = list(csv.DictReader(open("over-under-by-game.csv")))
by_sport = defaultdict(list)
for row in rows:
    by_sport[row["sport"]].append(row)


def interval(values: np.ndarray, weights: np.ndarray | None, rng: np.random.Generator) -> tuple[float, float]:
    """95% percentile interval of sum(values) / sum(weights), or of the mean when weights is None, resampling games."""
    n = len(values)
    picks = rng.integers(0, n, size=(DRAWS, n))
    if weights is None:
        stats = values[picks].mean(axis=1)
    else:
        stats = values[picks].sum(axis=1) / weights[picks].sum(axis=1)
    low, high = np.percentile(stats, [2.5, 97.5])
    return 100 * low, 100 * high


def report(label: str, games: list[dict], rng: np.random.Generator) -> None:
    lines = np.array([int(g["lines"]) for g in games], dtype=float)
    unders = np.array([int(g["unders"]) for g in games], dtype=float)
    share = 100 * unders.sum() / lines.sum()
    binomial = 100 * 1.959964 * math.sqrt(0.25 / lines.sum())
    lo, hi = interval(unders, lines, rng)

    traded = [g for g in games if g["main_volume_usd"] != ""]
    main = np.array([int(g["main_under"]) for g in traded], dtype=float)
    main_share = 100 * main.mean()
    main_half = 100 * 1.959964 * math.sqrt(main.mean() * (1 - main.mean()) / len(main))
    main_lo, main_hi = interval(main, None, rng)

    laddered = [g for g in games if g["middle_under"] != ""]
    middle = np.array([float(g["middle_under"]) for g in laddered], dtype=float)
    middle_share = 100 * middle.mean()
    middle_lo, middle_hi = interval(middle, None, rng)

    print(
        f"{label:<17} games {len(games):>6}  lines {int(lines.sum()):>6}  per_game {lines.sum() / len(games):5.2f}  "
        f"every_line {share:5.1f}% [{lo:5.1f}, {hi:5.1f}] (binomial +/- {binomial:4.2f})  "
        f"main_line {main_share:5.1f}% +/- {main_half:4.2f} [{main_lo:5.1f}, {main_hi:5.1f}] of {len(traded)}  "
        f"middle_rung {middle_share:5.1f}% [{middle_lo:5.1f}, {middle_hi:5.1f}] of {len(laddered)}"
    )


rng = np.random.default_rng(SEED)
print("== Settled game totals by game, kickoff 2026-04-02 to 2026-09-13")
report("All sports", rows, rng)
for sport, games in sorted(by_sport.items(), key=lambda item: -len(item[1])):
    if len(games) >= MIN_GAMES:
        report(LABELS.get(sport, sport), games, rng)
print(f"left out of the sport rows (under {MIN_GAMES} games): "
      + ", ".join(f"{sport} {len(games)}" for sport, games in sorted(by_sport.items()) if len(games) < MIN_GAMES))

print("\n== Soccer main lines")
soccer = [g for g in by_sport["Soccer"] if g["main_volume_usd"] != ""]
main_lines = defaultdict(lambda: [0, 0])
for game in soccer:
    main_lines[game["main_line"]][0] += 1
    main_lines[game["main_line"]][1] += int(game["main_under"])
for line, (count, under) in sorted(main_lines.items(), key=lambda item: -item[1][0])[:5]:
    rate = under / count
    half = 100 * 1.959964 * math.sqrt(rate * (1 - rate) / count)
    print(f"main line {line or '(none)':>6}  games {count:>6}  share {100 * count / len(soccer):5.1f}%  under {100 * rate:5.1f}% +/- {half:4.2f}")

print("\n== Checks")
single = [g for g in rows if g["main_volume_usd"] != "" and g["middle_under"] in ("0.00", "1.00")]
same = sum(1 for g in single if float(g["middle_under"]) == float(g["main_under"]))
print(f"games with no reported volume on any line (left out of the main line): {sum(1 for g in rows if g['main_volume_usd'] == '')}")
print(f"games without a laddered line (left out of the middle rung): {sum(1 for g in rows if g['middle_under'] == '')}")
print(f"games with a one-line middle rung whose main line settled the same way: {same} of {len(single)}")

print("\n== The first run's buy-level edges, intervals resampling games instead of markets")
print("Reads over-under-game-edge.csv (query 4). Same draws and seed as bootstrap-2026-09-13.py.")
edge_groups = defaultdict(list)
for row in csv.DictReader(open("over-under-game-edge.csv")):
    edge_groups[row["grp"]].append((int(row["n"]), float(row["sum_edge"])))
print(f"{'group':26} {'trades':>7} {'games':>6} {'edge_pts':>9}   95% CI")
for group in sorted(edge_groups):
    arr = np.array(edge_groups[group], dtype=float)
    n, s = arr[:, 0], arr[:, 1]
    point = 100 * s.sum() / n.sum()
    group_rng = np.random.default_rng(SEED)
    picks = group_rng.integers(0, len(arr), size=(DRAWS, len(arr)))
    draws = 100 * s[picks].sum(axis=1) / n[picks].sum(axis=1)
    low, high = np.percentile(draws, [2.5, 97.5])
    print(f"{group:26} {int(n.sum()):7d} {len(arr):6d} {point:9.2f}   [{low:+.2f}, {high:+.2f}]")
