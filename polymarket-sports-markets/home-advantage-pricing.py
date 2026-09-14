"""The pricing half of the home advantage study, recounted with ESPN's home team.

Inputs:
  home-advantage-buys.csv                        per-buy export from home-advantage-recount.sql
                                                 (not committed: 11.8 MB; the query regenerates it)
  home-espn-check.csv          every US game matched to ESPN's schedule
A US buy counts when its game counts under home-espn-recount.py (ESPN match, regular season or
postseason, no neutral site, one market per game); its side is Home when it bought ESPN's home team. Soccer buys
keep the study's side (the home team named first in the draw market). The tables follow the #13781 study's
queries 5 and 6; intervals resample markets (5,000 draws, seed 20260913), as bootstrap-2026-09-13.py does.

Outputs: the tables on stdout and home-advantage-recount-market-edge.csv (the bootstrap input).
Usage: python3 home-advantage-pricing.py home-advantage-buys.csv home-espn-check.csv
"""

import csv
import importlib.util
import os
import sys
from collections import defaultdict

import numpy as np

DRAWS = 5000
SEED = 20260913

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("recount", os.path.join(here, "home-espn-recount.py"))
recount = importlib.util.module_from_spec(spec)
spec.loader.exec_module(recount)


def main(buys_path, check_path):
    counted, _ = recount.count_games(list(csv.DictReader(open(check_path))))
    home_index = {row["condition_id"]: row["home_outcome_index"] for row in counted}
    us_leagues = {"nba", "nhl", "mlb", "wnba", "nfl", "cfb"}

    buys = []
    left_out = defaultdict(int)
    changed_side = defaultdict(int)
    for row in csv.DictReader(open(buys_path)):
        league = row["league"]
        if league in us_leagues:
            if row["condition_id"] not in home_index:
                left_out[league] += 1
                continue
            side = "Home" if int(row["outcome_index"]) == home_index[row["condition_id"]] else "Away"
            if side != row["title_side"]:
                changed_side[league] += 1
        else:
            side = row["title_side"]
        buys.append({
            "league": league,
            "condition_id": row["condition_id"],
            "side": side,
            "price": float(row["price_num"]),
            "stake": float(row["usdc_notional_num"]),
            "won": int(row["won"]),
            "in_play": int(row["in_play"]),
        })

    print("== Buys of games the recount leaves out, by league:", dict(sorted(left_out.items())))
    print("== Counted buys whose side the recount changes, by league:", dict(sorted(changed_side.items())))
    stakes = sum(buy["stake"] for buy in buys)
    print(
        f"== Sample: buys {len(buys)}  markets {len({buy['condition_id'] for buy in buys})}  "
        f"notional_musd {stakes / 1e6:.1f}  in_play_pct {100 * np.mean([buy['in_play'] for buy in buys]):.1f}"
    )

    def summary(rows):
        price = np.array([row["price"] for row in rows])
        won = np.array([row["won"] for row in rows])
        stake = np.array([row["stake"] for row in rows])
        return {
            "buys": len(rows),
            "markets": len({row["condition_id"] for row in rows}),
            "notional_musd": stake.sum() / 1e6,
            "avg_price_c": 100 * price.mean(),
            "win_pct": 100 * won.mean(),
            "edge_pts": 100 * (won.mean() - price.mean()),
            "dollar_roi_pct": 100 * (stake * (won / price - 1)).sum() / stake.sum(),
        }

    groups = defaultdict(list)
    for buy in buys:
        groups[f"{buy['league']} | {buy['side']}"].append(buy)
        groups[f"All leagues | {buy['side']}"].append(buy)
        band = "underdog" if buy["price"] < 0.5 else "favorite"
        groups[f"{buy['side']} priced as {band}"].append(buy)

    print("\n== By group (query 5 and 6 columns)")
    print(f"{'group':28} {'buys':>7} {'markets':>7} {'notional':>9} {'price':>6} {'win':>6} {'edge':>7} {'roi':>7}")
    for name in sorted(groups):
        s = summary(groups[name])
        print(
            f"{name:28} {s['buys']:7d} {s['markets']:7d} {s['notional_musd']:9.1f} {s['avg_price_c']:6.1f} "
            f"{s['win_pct']:6.1f} {s['edge_pts']:7.2f} {s['dollar_roi_pct']:7.2f}"
        )

    with open("home-advantage-recount-market-edge.csv", "w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["group", "condition_id", "n", "sum_edge"])
        for name in sorted(groups):
            per_market = defaultdict(lambda: [0, 0.0])
            for row in groups[name]:
                per_market[row["condition_id"]][0] += 1
                per_market[row["condition_id"]][1] += row["won"] - row["price"]
            for condition_id, (count, sum_edge) in sorted(per_market.items()):
                writer.writerow([name, condition_id, count, f"{sum_edge:.6f}"])

    print(f"\n== Bootstrap ({DRAWS} draws, seed {SEED}, resampled over markets)")
    print(f"{'group':28} {'trades':>7} {'markets':>8} {'edge_pts':>9}   95% CI")
    for name in sorted(groups):
        per_market = defaultdict(lambda: [0, 0.0])
        for row in groups[name]:
            per_market[row["condition_id"]][0] += 1
            per_market[row["condition_id"]][1] += row["won"] - row["price"]
        arr = np.array(list(per_market.values()), dtype=float)
        n, total = arr[:, 0], arr[:, 1]
        point = total.sum() / n.sum() * 100
        rng = np.random.default_rng(SEED)
        index = rng.integers(0, len(arr), size=(DRAWS, len(arr)))
        draws = total[index].sum(axis=1) / n[index].sum(axis=1) * 100
        lo, hi = np.percentile(draws, [2.5, 97.5])
        print(f"{name:28} {int(n.sum()):7d} {len(arr):8d} {point:9.2f}   [{lo:+.2f}, {hi:+.2f}]")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
