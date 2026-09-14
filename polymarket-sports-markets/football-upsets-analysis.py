"""Football upsets on Polymarket: how often the team priced below 50 cents at kickoff won.

Inputs, published beside this script:
  football-games.csv       the read-only export of settled NFL and college football moneylines
  football-scoreboard.csv  each game matched to ESPN's final score, season type and venue
  football-prices.csv      the away team's last price before kickoff, from the public CLOB
Output: the tables below on stdout, and football-upsets-games.csv (one row per counted game).

A game counts when ESPN lists it as a completed regular-season or postseason game (preseason left out), the
market's settlement names ESPN's winner, the moneyline traded at least $10,000 (Polymarket's reported volume; a
thinner market's last price is not a price anyone could trade size at: the South Dakota Mines and Drake moneyline
traded $946), and the away team's last price is within 60 minutes of the cutoff (the earlier of Polymarket's and
ESPN's listed start). The favorite is the team priced above 50 cents at that moment;
a game priced exactly 50-50 is left out. The home team is ESPN's; home and road splits leave out neutral sites.
  edge          the favorite's (or underdog's) win rate minus its average kickoff price, in percentage points
  flat return   the average profit of $1 staked on that side in every game at its kickoff price, in percent
  fee           Polymarket's sports taker fee, 0.05 x p x (1 - p) USDC a share, is 0.05 x (1 - p) on $1 at price p
Intervals resample games: 5,000 draws, seed 20260913. Rates carry a binomial 95% half-width.

Usage: python3 football-upsets-analysis.py
"""

import csv
from collections import defaultdict

import numpy as np

MIN_VOLUME_USD = 10_000
UPSET_LIST_MIN_VOLUME_USD = 50_000
DRAWS = 5000
SEED = 20260913
Z = 1.959964
LEAGUES = (("nfl", "NFL"), ("cfb", "College football"))

games = {row["condition_id"]: row for row in csv.DictReader(open("football-games.csv"))}
scoreboard = {row["condition_id"]: row for row in csv.DictReader(open("football-scoreboard.csv"))}
prices = {row["condition_id"]: row for row in csv.DictReader(open("football-prices.csv"))}

left_out = defaultdict(int)
rows = []
# Games the $10,000 floor leaves out, kept apart to report what the floor changes.
thin_rows = []
for condition_id, game in games.items():
    board = scoreboard[condition_id]
    price = prices[condition_id]
    league = game["league"]
    if not board["espn_id"]:
        left_out[(league, "no ESPN match")] += 1
        continue
    if board["season_type"] not in ("2", "3"):
        left_out[(league, "preseason")] += 1
        continue
    if board["winner_agrees"] != "1":
        left_out[(league, "settlement disagrees with ESPN")] += 1
        continue
    if price["kickoff_price"] == "" or float(price["minutes_before"]) > 60:
        left_out[(league, "no price within 60 minutes of kickoff")] += 1
        continue
    away_price = float(price["kickoff_price"])
    if away_price == 0.5:
        left_out[(league, "priced exactly 50-50")] += 1
        continue
    thin = float(game["volume_usd"]) < MIN_VOLUME_USD
    if thin:
        left_out[(league, "moneyline volume under $10,000")] += 1
    away_won = game["winning_outcome"] == "0"
    away_is_favorite = away_price > 0.5
    favorite_price = away_price if away_is_favorite else 1 - away_price
    favorite_won = away_won if away_is_favorite else not away_won
    first_named_is_espn_away = board["away_is_away"] == "1"
    # Polymarket's first-named team is `away` in the export; ESPN decides which team was at home.
    favorite_is_home = (not away_is_favorite) if first_named_is_espn_away else away_is_favorite
    day_before = float(price["day_before_price"]) if price["day_before_price"] else away_price
    (thin_rows if thin else rows).append({
        "condition_id": condition_id,
        "event_slug": game["event_slug"],
        "league": league,
        "season_type": board["season_type"],
        "neutral_site": int(board["neutral_site"]),
        "game_start_utc": game["game_start_utc"],
        "favorite": game["away"] if away_is_favorite else game["home"],
        "underdog": game["home"] if away_is_favorite else game["away"],
        "favorite_price": favorite_price,
        "favorite_won": int(favorite_won),
        "favorite_is_home": int(favorite_is_home),
        "favorite_day_before_price": day_before if away_is_favorite else 1 - day_before,
        "favorite_score": int(board["away_score"]) if away_is_favorite else int(board["home_score"]),
        "underdog_score": int(board["home_score"]) if away_is_favorite else int(board["away_score"]),
        "volume_usd": float(game["volume_usd"]),
    })


def rate(values):
    values = np.asarray(values, dtype=float)
    p = values.mean()
    return 100 * p, 100 * Z * np.sqrt(p * (1 - p) / len(values))


def bootstrap(statistic, *columns):
    arrays = [np.asarray(column, dtype=float) for column in columns]
    size = len(arrays[0])
    index = np.random.default_rng(SEED).integers(0, size, size=(DRAWS, size))
    return np.percentile(statistic(*[array[index] for array in arrays]), [2.5, 97.5])


def side_row(label, subset, side):
    """`side` is "favorite" or "underdog"; prices and outcomes are read from that side."""
    if not subset:
        print(f"{label:34} games     0")
        return
    fav_price = np.array([row["favorite_price"] for row in subset])
    fav_won = np.array([row["favorite_won"] for row in subset], dtype=float)
    price = fav_price if side == "favorite" else 1 - fav_price
    won = fav_won if side == "favorite" else 1 - fav_won
    pct, half = rate(won)
    edge = 100 * (won.mean() - price.mean())
    e_lo, e_hi = bootstrap(lambda w, p: 100 * (w.mean(axis=-1) - p.mean(axis=-1)), won, price)
    flat = 100 * np.mean(won / price - 1)
    f_lo, f_hi = bootstrap(lambda w, p: 100 * np.mean(w / p - 1, axis=-1), won, price)
    after = 100 * np.mean(won / price - 1 - 0.05 * (1 - price))
    a_lo, a_hi = bootstrap(lambda w, p: 100 * np.mean(w / p - 1 - 0.05 * (1 - p), axis=-1), won, price)
    print(
        f"{label:34} games {len(subset):5d}  {side:8} price {100 * price.mean():6.2f}c  won {pct:5.1f}% +/- {half:5.2f}  "
        f"edge {edge:+6.2f} [{e_lo:+.2f}, {e_hi:+.2f}]  flat {flat:+7.2f}% [{f_lo:+.2f}, {f_hi:+.2f}]  after_fee {after:+7.2f}% [{a_lo:+.2f}, {a_hi:+.2f}]"
    )


print("== Left out, by league and reason")
for (league, reason), number in sorted(left_out.items()):
    print(f"{league:4} {reason:40} {number:5d}")

print("\n== Sample")
for league, name in LEAGUES:
    subset = [row for row in rows if row["league"] == league]
    first = min(row["game_start_utc"] for row in subset)[:10]
    last = max(row["game_start_utc"] for row in subset)[:10]
    postseason = sum(1 for row in subset if row["season_type"] == "3")
    neutral = sum(row["neutral_site"] for row in subset)
    print(f"{name:17} games {len(subset):5d}  postseason {postseason:3d}  neutral_site {neutral:3d}  {first} to {last}")

print("\n== Underdogs won, by league")
for league, name in LEAGUES:
    subset = [row for row in rows if row["league"] == league]
    side_row(f"{name}: all games", subset, "underdog")
    side_row(f"{name}: all games", subset, "favorite")

print("\n== By the favorite's kickoff price")
bands = (("50c to 60c", 0.5, 0.6), ("60c to 70c", 0.6, 0.7), ("70c to 80c", 0.7, 0.8), ("80c to 90c", 0.8, 0.9), ("90c and up", 0.9, 1.01))
for league, name in LEAGUES:
    for label, lo, hi in bands:
        subset = [row for row in rows if row["league"] == league and lo <= row["favorite_price"] < hi]
        side_row(f"{name}: favorite {label}", subset, "favorite")

print("\n== Home and road underdogs (neutral sites left out)")
for league, name in LEAGUES:
    for home, label in ((0, "home underdog"), (1, "road underdog")):
        subset = [row for row in rows if row["league"] == league and row["neutral_site"] == 0 and row["favorite_is_home"] == home]
        side_row(f"{name}: {label}", subset, "underdog")

print("\n== What the $10,000 floor changes: college road underdogs with and without the thin markets")
side_row("College: road underdogs, first cut", [row for row in rows + thin_rows if row["league"] == "cfb" and row["neutral_site"] == 0 and row["favorite_is_home"] == 1], "underdog")
side_row("College: road underdogs, thin only", [row for row in thin_rows if row["league"] == "cfb" and row["neutral_site"] == 0 and row["favorite_is_home"] == 1], "underdog")
side_row("College: all underdogs, first cut", [row for row in rows + thin_rows if row["league"] == "cfb"], "underdog")

print("\n== Price move in the 24 hours before kickoff, from the favorite's side")
moves = (("favorite price fell 3c or more", lambda d: d <= -0.03), ("moved less than 3c", lambda d: -0.03 < d < 0.03), ("favorite price rose 3c or more", lambda d: d >= 0.03))
for league, name in LEAGUES:
    for label, test in moves:
        subset = [row for row in rows if row["league"] == league and test(row["favorite_price"] - row["favorite_day_before_price"])]
        if not subset:
            continue
        won = np.array([row["favorite_won"] for row in subset], dtype=float)
        early = np.array([row["favorite_day_before_price"] for row in subset])
        late = np.array([row["favorite_price"] for row in subset])
        pct, half = rate(won)
        e_lo, e_hi = bootstrap(lambda w, p: 100 * (w.mean(axis=-1) - p.mean(axis=-1)), won, early)
        l_lo, l_hi = bootstrap(lambda w, p: 100 * (w.mean(axis=-1) - p.mean(axis=-1)), won, late)
        print(
            f"{name}: {label:32} games {len(subset):5d}  earliest {100 * early.mean():6.2f}c  kickoff {100 * late.mean():6.2f}c  favorite_won {pct:5.1f}% +/- {half:5.2f}  "
            f"edge_at_earliest {100 * (won.mean() - early.mean()):+6.2f} [{e_lo:+.2f}, {e_hi:+.2f}]  edge_at_kickoff {100 * (won.mean() - late.mean()):+6.2f} [{l_lo:+.2f}, {l_hi:+.2f}]"
        )

print("\n== The biggest upsets: lowest kickoff price for the team that won, moneylines that traded $50,000 or more")
for league, name in LEAGUES:
    upsets = sorted(
        (row for row in rows if row["league"] == league and row["favorite_won"] == 0 and row["volume_usd"] >= UPSET_LIST_MIN_VOLUME_USD),
        key=lambda row: 1 - row["favorite_price"],
    )
    for row in upsets[:10]:
        print(
            f"{name:17} {row['game_start_utc'][:10]}  {row['underdog']} beat {row['favorite']}  underdog price {100 * (1 - row['favorite_price']):.1f}c  "
            f"score {row['underdog_score']}-{row['favorite_score']}  volume ${row['volume_usd']:,.0f}  {row['event_slug']}"
        )

with open("football-upsets-games.csv", "w", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
    writer.writeheader()
    writer.writerows(rows)
print(f"\nwrote football-upsets-games.csv ({len(rows)} games)")
