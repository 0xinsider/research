"""NRFI study analysis: first-inning splits, teams, and first-pitch prices against results.

Inputs, all published beside this script:
  nrfi-markets.csv     the read-only export of settled NRFI markets (query 9)
  nrfi-linescores.csv  the MLB game each market settled on, with first-inning runs
  nrfi-prices.csv      the no-run price before first pitch, from the public CLOB
Output: the tables below on stdout, and nrfi-games.csv (one row per game).

Definitions.
  no_run            1 when no run scored in the first inning, read from the market's settlement
                    (the linescore cross-check agrees on every game).
  first-pitch price the no-run token's last price at or before the earlier of Polymarket's and MLB's
                    listed start. Pricing rows leave out the three postponed games, which were played
                    16 to 42 hours after the listed start, and any game whose last price is more than
                    60 minutes before that start.
  edge              no-run rate minus the average price, in percentage points. Buying the run side at
                    the same moment has the opposite edge before the spread and fees.
  flat return       the average profit of $1 staked on a side at its first-pitch price, as a percentage.
  fee               Polymarket's sports taker fee, 0.05 x p x (1 - p) USDC a share, is 0.05 x (1 - p) on
                    $1 staked at price p.
Intervals resample games: 5,000 draws, seed 20260913. Rates carry a binomial 95% half-width.

Usage: python3 nrfi-analysis.py
"""

import csv
from collections import defaultdict

import numpy as np

DRAWS = 5000
SEED = 20260913
Z = 1.959964

markets = {row["condition_id"]: row for row in csv.DictReader(open("nrfi-markets.csv"))}
linescores = {row["condition_id"]: row for row in csv.DictReader(open("nrfi-linescores.csv"))}
prices = {row["condition_id"]: row for row in csv.DictReader(open("nrfi-prices.csv"))}

games = []
for condition_id, market in markets.items():
    line = linescores[condition_id]
    price = prices[condition_id]
    yes_won = market["winning_outcome"] == "0"
    no_run = int(yes_won if market["fmt"] == "yes_is_no_run" else not yes_won)
    games.append({
        "condition_id": condition_id,
        "event_slug": market["event_slug"],
        "season": "2025" if market["game_start_utc"] < "2026-01-01" else "2026",
        "game_start_utc": market["game_start_utc"],
        "away_team": line["away_team"],
        "home_team": line["home_team"],
        "away_runs_first": int(line["away_runs_first"]),
        "home_runs_first": int(line["home_runs_first"]),
        "no_run": no_run,
        "postponed": int(line["followed_postponement"]),
        "first_pitch_price": float(price["first_pitch_price"]),
        "minutes_before": float(price["minutes_before"]),
        "day_before_price": float(price["day_before_price"]),
    })

rng_seed = np.random.default_rng


def rate(values):
    values = np.asarray(values, dtype=float)
    p = values.mean()
    return 100 * p, 100 * Z * np.sqrt(p * (1 - p) / len(values))


def bootstrap(statistic, *columns):
    arrays = [np.asarray(column, dtype=float) for column in columns]
    size = len(arrays[0])
    rng = rng_seed(SEED)
    index = rng.integers(0, size, size=(DRAWS, size))
    draws = statistic(*[array[index] for array in arrays])
    return np.percentile(draws, [2.5, 97.5])


def edge_row(label, rows):
    outcome = np.array([row["no_run"] for row in rows], dtype=float)
    price = np.array([row["first_pitch_price"] for row in rows], dtype=float)
    edge = 100 * (outcome.mean() - price.mean())
    lo, hi = bootstrap(lambda o, p: 100 * (o.mean(axis=-1) - p.mean(axis=-1)), outcome, price)
    no_run_return = 100 * np.mean(outcome / price - 1)
    run_return = 100 * np.mean((1 - outcome) / (1 - price) - 1)
    nr_lo, nr_hi = bootstrap(lambda o, p: 100 * np.mean(o / p - 1, axis=-1), outcome, price)
    r_lo, r_hi = bootstrap(lambda o, p: 100 * np.mean((1 - o) / (1 - p) - 1, axis=-1), outcome, price)
    no_run_after_fee = 100 * np.mean(outcome / price - 1 - 0.05 * (1 - price))
    run_after_fee = 100 * np.mean((1 - outcome) / (1 - price) - 1 - 0.05 * price)
    nrf_lo, nrf_hi = bootstrap(lambda o, p: 100 * np.mean(o / p - 1 - 0.05 * (1 - p), axis=-1), outcome, price)
    rf_lo, rf_hi = bootstrap(lambda o, p: 100 * np.mean((1 - o) / (1 - p) - 1 - 0.05 * p, axis=-1), outcome, price)
    pct, half = rate(outcome)
    print(
        f"{label:28} games {len(rows):5d}  avg_price {100 * price.mean():6.2f}c  no_run {pct:5.1f}% +/- {half:5.2f}  "
        f"edge {edge:+6.2f} [{lo:+.2f}, {hi:+.2f}]  no_run_return {no_run_return:+6.2f}% [{nr_lo:+.2f}, {nr_hi:+.2f}]  "
        f"run_return {run_return:+6.2f}% [{r_lo:+.2f}, {r_hi:+.2f}]  fee_per_$1_no_run {100 * np.mean(0.05 * (1 - price)):.2f}c  fee_per_$1_run {100 * np.mean(0.05 * price):.2f}c\n"
        f"{'':28} after the taker fee: no_run_return {no_run_after_fee:+6.2f}% [{nrf_lo:+.2f}, {nrf_hi:+.2f}]  run_return {run_after_fee:+6.2f}% [{rf_lo:+.2f}, {rf_hi:+.2f}]"
    )


print("== 1. First-inning outcomes, all games (MLB linescores)")
all_games = games
n = len(all_games)
away_scored = [int(row["away_runs_first"] > 0) for row in all_games]
home_scored = [int(row["home_runs_first"] > 0) for row in all_games]
both = [a * h for a, h in zip(away_scored, home_scored)]
neither = [int(row["away_runs_first"] + row["home_runs_first"] == 0) for row in all_games]
for label, values in (("away team scored in the top", away_scored), ("home team scored in the bottom", home_scored), ("both teams scored", both), ("no run (NRFI)", neither)):
    pct, half = rate(values)
    print(f"{label:32} {sum(values):5d} of {n}  {pct:5.1f}% +/- {half:.2f}")
print("agreement: linescore no-run equals market no-run on", sum(int(v == row["no_run"]) for v, row in zip(neither, all_games)), "of", n)
runs = defaultdict(int)
for row in all_games:
    total = row["away_runs_first"] + row["home_runs_first"]
    runs["4+" if total >= 4 else str(total)] += 1
for key in ("0", "1", "2", "3", "4+"):
    print(f"first-inning runs {key:>2}: {runs[key]:5d} games  {100 * runs[key] / n:5.1f}%")
scoring_games = [row for row in all_games if row["away_runs_first"] + row["home_runs_first"] > 0]
print(f"games with a first-inning run {len(scoring_games)}, average runs in those games {np.mean([row['away_runs_first'] + row['home_runs_first'] for row in scoring_games]):.2f}")
for season in ("2025", "2026"):
    subset = [row for row in all_games if row["season"] == season]
    a = rate([int(row["away_runs_first"] > 0) for row in subset])
    h = rate([int(row["home_runs_first"] > 0) for row in subset])
    print(f"season {season}: games {len(subset)}  away scored {a[0]:.1f}%  home scored {h[0]:.1f}%")

print("\n== 2. Teams, every game a team played (MLB team names)")
team_rows = defaultdict(lambda: {"games": 0, "scored": 0, "allowed": 0, "no_run": 0, "home_games": 0, "home_no_run": 0})
for row in all_games:
    for team, scored, allowed in (
        (row["away_team"], row["away_runs_first"] > 0, row["home_runs_first"] > 0),
        (row["home_team"], row["home_runs_first"] > 0, row["away_runs_first"] > 0),
    ):
        record = team_rows[team]
        record["games"] += 1
        record["scored"] += int(scored)
        record["allowed"] += int(allowed)
        record["no_run"] += row["no_run"]
    record = team_rows[row["home_team"]]
    record["home_games"] += 1
    record["home_no_run"] += row["no_run"]
ordered = sorted(team_rows.items(), key=lambda item: -item[1]["no_run"] / item[1]["games"])
print(f"{'team':24} {'games':>5} {'scored_1st':>10} {'allowed_1st':>11} {'no_run':>7} {'half_w':>6} {'home_games':>10} {'home_no_run':>11}")
for team, record in ordered:
    g = record["games"]
    p = record["no_run"] / g
    print(f"{team:24} {g:5d} {100 * record['scored'] / g:9.1f}% {100 * record['allowed'] / g:10.1f}% {100 * p:6.1f}% {100 * Z * np.sqrt(p * (1 - p) / g):6.2f} {record['home_games']:10d} {100 * record['home_no_run'] / record['home_games']:10.1f}%")

# Is the spread across teams wider than chance? Simulate every game with one league-wide probability for
# each half-inning, keep the real schedule, and compare the standard deviation of team rates.
teams = sorted(team_rows)
team_index = {team: i for i, team in enumerate(teams)}
away_idx = np.array([team_index[row["away_team"]] for row in all_games])
home_idx = np.array([team_index[row["home_team"]] for row in all_games])
games_per_team = np.bincount(away_idx, minlength=len(teams)) + np.bincount(home_idx, minlength=len(teams))
p_top = np.mean(away_scored)
p_bottom = np.mean(home_scored)


def team_spreads(top, bottom):
    scored = np.zeros((top.shape[0], len(teams)))
    allowed = np.zeros((top.shape[0], len(teams)))
    no_run = np.zeros((top.shape[0], len(teams)))
    neither_mask = (1 - top) * (1 - bottom)
    for t in range(len(teams)):
        as_away = away_idx == t
        as_home = home_idx == t
        scored[:, t] = top[:, as_away].sum(axis=1) + bottom[:, as_home].sum(axis=1)
        allowed[:, t] = bottom[:, as_away].sum(axis=1) + top[:, as_home].sum(axis=1)
        no_run[:, t] = neither_mask[:, as_away].sum(axis=1) + neither_mask[:, as_home].sum(axis=1)
    return [np.std(values / games_per_team, axis=1) for values in (scored, allowed, no_run)]


observed_top = np.array(away_scored, dtype=float)[None, :]
observed_bottom = np.array(home_scored, dtype=float)[None, :]
observed = [values[0] for values in team_spreads(observed_top, observed_bottom)]
rng = rng_seed(SEED)
simulated_top = (rng.random((DRAWS, n)) < p_top).astype(float)
simulated_bottom = (rng.random((DRAWS, n)) < p_bottom).astype(float)
simulated = team_spreads(simulated_top, simulated_bottom)
for label, obs, sims in zip(("scored in the first", "allowed a run in the first", "no run in the first"), observed, simulated):
    print(f"team spread, {label:28}: observed sd {100 * obs:.2f} pts, chance sd median {100 * np.median(sims):.2f} pts, share of simulations at least as wide {np.mean(sims >= obs):.4f}")

print("\n== 3. First-pitch prices")
priced = [row for row in all_games if row["postponed"] == 0 and row["minutes_before"] <= 60]
print(f"games {n}, postponed left out {sum(row['postponed'] for row in all_games)}, last price more than 60 minutes before the start left out {sum(1 for row in all_games if row['postponed'] == 0 and row['minutes_before'] > 60)}, priced {len(priced)}")
first_pitch = np.array([row["first_pitch_price"] for row in priced])
print(f"no-run price at first pitch: mean {100 * first_pitch.mean():.2f}c, median {100 * np.median(first_pitch):.2f}c, 10th pct {100 * np.percentile(first_pitch, 10):.2f}c, 90th pct {100 * np.percentile(first_pitch, 90):.2f}c, between 45c and 60c {100 * np.mean((first_pitch >= 0.45) & (first_pitch < 0.60)):.1f}%")
edge_row("all priced games", priced)
for season in ("2025", "2026"):
    edge_row(f"season {season}", [row for row in priced if row["season"] == season])

print("\n== 4. By first-pitch no-run price")
bands = (("under 45c", 0.0, 0.45), ("45c to 50c", 0.45, 0.50), ("50c to 55c", 0.50, 0.55), ("55c to 60c", 0.55, 0.60), ("60c and up", 0.60, 1.01))
for label, lo, hi in bands:
    edge_row(label, [row for row in priced if lo <= row["first_pitch_price"] < hi])

print("\n== 5. Does the price know more than the league rate?")
outcome = np.array([row["no_run"] for row in priced], dtype=float)
base = outcome.mean()
brier_price = np.mean((first_pitch - outcome) ** 2)
brier_base = np.mean((base - outcome) ** 2)
lo, hi = bootstrap(lambda o, p: np.mean((o.mean(axis=-1, keepdims=True) - o) ** 2, axis=-1) - np.mean((p - o) ** 2, axis=-1), outcome, first_pitch)
print(f"brier: first-pitch price {brier_price:.5f}, one league rate {brier_base:.5f} ({100 * base:.1f}%), improvement {brier_base - brier_price:.5f} [{lo:.5f}, {hi:.5f}], skill {100 * (1 - brier_price / brier_base):.2f}%")
low = [row for row in priced if row["first_pitch_price"] < 0.50]
high = [row for row in priced if row["first_pitch_price"] >= 0.50]
low_rate = rate([row["no_run"] for row in low])
high_rate = rate([row["no_run"] for row in high])
print(f"priced under 50c: {len(low)} games, no run {low_rate[0]:.1f}% +/- {low_rate[1]:.2f}; priced 50c and up: {len(high)} games, no run {high_rate[0]:.1f}% +/- {high_rate[1]:.2f}")

print("\n== 6. The price move over the 24 hours before first pitch")
moves = (("no-run price fell 3c or more", lambda d: d <= -0.03), ("moved less than 3c", lambda d: -0.03 < d < 0.03), ("no-run price rose 3c or more", lambda d: d >= 0.03))
for label, test in moves:
    rows = [row for row in priced if test(row["first_pitch_price"] - row["day_before_price"])]
    outcome_move = np.array([row["no_run"] for row in rows], dtype=float)
    early = np.array([row["day_before_price"] for row in rows], dtype=float)
    late = np.array([row["first_pitch_price"] for row in rows], dtype=float)
    pct, half = rate(outcome_move)
    e_lo, e_hi = bootstrap(lambda o, p: 100 * (o.mean(axis=-1) - p.mean(axis=-1)), outcome_move, early)
    l_lo, l_hi = bootstrap(lambda o, p: 100 * (o.mean(axis=-1) - p.mean(axis=-1)), outcome_move, late)
    print(
        f"{label:30} games {len(rows):5d}  earliest {100 * early.mean():6.2f}c  first_pitch {100 * late.mean():6.2f}c  no_run {pct:5.1f}% +/- {half:5.2f}  "
        f"edge_at_earliest {100 * (outcome_move.mean() - early.mean()):+6.2f} [{e_lo:+.2f}, {e_hi:+.2f}]  edge_at_first_pitch {100 * (outcome_move.mean() - late.mean()):+6.2f} [{l_lo:+.2f}, {l_hi:+.2f}]"
    )

with open("nrfi-games.csv", "w", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=list(games[0].keys()))
    writer.writeheader()
    writer.writerows(games)
print(f"\nwrote nrfi-games.csv ({len(games)} rows)")
