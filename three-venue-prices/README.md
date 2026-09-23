# Three-venue prices: the same games on Polymarket, Kalshi and DraftKings

Published 2026-09-18 on the site (issue 0xinsider/0xinsider#14883):

- https://0xinsider.com/research/use-0xinsider-for-kalshi-draftkings

One capture, 16:01:03 to 16:01:11 UTC on 2026-09-18, of three public endpoints that need no key:
Polymarket's Gamma market list, Kalshi's trade API event list, and ESPN's scoreboard, which publishes
the DraftKings line for each game. It covers NFL, college football, MLB and WNBA games starting
September 18 to 21, 2026, moneylines only, all before the start.

## Headlines

| Measure | Result |
|---|---|
| Games priced on all three venues | 81 (49 college football, 15 NFL, 14 MLB, 3 WNBA) |
| Polymarket against Kalshi | identical midpoint on 57 of 81; within 1 point on 84.0%; widest 2.00 |
| Polymarket against DraftKings, margin removed proportionally | median 0.99 pts; within 3 on 97.5%; widest 3.20 |
| The same, margin removed as equal cents per side | median 0.66 pts; within 1 on 70.4% |
| Polymarket above the proportional DraftKings price on the favorite | 64 of 81 games; +0.20 pts at 50 to 60%, +1.66 at 90% and up |
| DraftKings overround | median 4.25 pts (3.11 to 4.83) |
| Polymarket, both sides at the ask plus the 0.05 sports taker fee | median 3.16 cents; under the overround in 80 of 81 |
| Quoted spread | 1 cent at the median on both Polymarket and Kalshi |

No game had been played at the capture, so this measures agreement between prices, not accuracy. All 81
have since been played and are scored below, under "Which price was right". No Kalshi trading fee is
modelled.

## Files

- `capture.py` reads the three endpoints and writes the fields the analysis uses, unconverted.
- `capture.json` is the capture the published figures come from.
- `analysis.py` pairs the games across venues and prints the report.
- `analysis-output.txt` is that report.
- `games.csv` has one row for each of the 81 games.

## Reproducing

No database and no account. Python 3.10 or later, standard library only.

```
cd three-venue-prices
python3 analysis.py capture.json | diff - analysis-output.txt    # no output means it reproduces
python3 capture.py fresh.json && python3 analysis.py fresh.json  # a new sample, live prices
```

A fresh capture is a different sample, because these are live prices and the schedule moves.

## Definitions

Every probability is the home team's. Polymarket and Kalshi are the midpoint of the best bid and the
best ask. DraftKings' American odds convert to an implied probability (100 / (odds + 100) for a plus
price, |odds| / (|odds| + 100) for a minus price); the two sides sum to more than 1 and the excess is
the overround. The fair price divides each side by the sum; the equal-cents variant subtracts half the
overround from each side. A doubleheader, where one date holds the same two teams twice, is dropped
rather than guessed.

## Which price was right (added 2026-09-23, issue 0xinsider/0xinsider#14900)

- https://0xinsider.com/research/use-0xinsider-for-kalshi-draftkings

All 81 games above are final. The sample is the one the capture fixed on 2026-09-18: the same 81 games,
none added and none dropped once the results were known. Each final was read from ESPN's scoreboard on
2026-09-23 by the ESPN event id `capture.json` already held, so no game was matched by name after the
fact. The home team won 48 of 81. No game ended in a tie.

Every score is on the home team's probability. Brier is the mean of (p - y)^2; log loss is the mean of
-(y ln p + (1 - y) ln(1 - p)), in nats. Lower is better on both. No price needed clipping.

| Price | Mean home price | Brier | Log loss |
|---|---:|---:|---:|
| Polymarket | 61.40% | 0.1502 | 0.4571 |
| Kalshi | 61.42% | 0.1504 | 0.4573 |
| DraftKings, margin removed proportionally | 60.80% | 0.1510 | 0.4618 |
| DraftKings, margin removed as equal cents | 61.23% | 0.1499 | 0.4567 |
| The home rate (59.26%) on every game | 59.26% | 0.2414 | 0.6759 |
| A coin on every game | 50.00% | 0.2500 | 0.6931 |

All three venues beat a price with no game-level information by a wide margin, and none of them is
separable from the others. Each pairwise difference is taken game by game and averaged, with an interval
from resampling the 81 games with replacement 20,000 times (seed 14900, 2.5th to 97.5th percentile):

| Difference | Brier | Interval | Log loss | Interval |
|---|---:|---|---:|---|
| Polymarket minus DraftKings | -0.00084 | -0.00271 to +0.00115 | -0.00472 | -0.00993 to +0.00115 |
| Kalshi minus DraftKings | -0.00064 | -0.00254 to +0.00144 | -0.00447 | -0.00979 to +0.00161 |
| Polymarket minus Kalshi | -0.00020 | -0.00110 to +0.00074 | -0.00025 | -0.00214 to +0.00170 |

Every interval spans zero. Holding the per-game spread where this sample put it, a Polymarket-to-DraftKings
gap this size stops spanning zero at around 425 games on Brier; between the two exchanges it takes around
1,658. This sample is 81 games over one weekend across four leagues, so it cannot order the three venues,
and nothing here should be read as doing so.

Favorites won 65 of 81. Banded by what each venue charged for its own favorite, the prices sat close to
the record: on DraftKings, favorites priced 50 to 60% won 17 of 25, 12.6 points above the 55.36% the price
implied, which is 1.27 standard errors on that band; favorites priced 90% and up won 14 of 14. Every
venue's near-even band came in high and every venue's heaviest band went undefeated, on bands of 13 to 26
games.

### The disagreement test, and its confound

In the 10 games where Polymarket sat furthest from the DraftKings fair price (2.25 to 3.20 points apart),
the side Polymarket leaned toward won all 10, with a Brier of 0.0281 against DraftKings' 0.0358. That is a
fact about the margin, not about Polymarket. Removing a sportsbook's margin **proportionally** leaves the
exchange above DraftKings on the favorite in 64 of 81 games, and favorites won 65 of 81, so a lean toward
the favorite is right about four times in five before any venue shows judgment -- and all 10 of those leans
pointed at the favorite.

Remove the same margin as **equal cents** per side and the test reverses. Polymarket's lean then points at
the favorite in 40 of 81 games rather than 64, and it names the winning side in 36 of 81, worse than a coin;
in the ten widest disagreements on that measure it is right in 6 of 10, being 6 of 6 where it leaned to the
favorite and 0 of 4 where it leaned to the underdog.

So the answer to which price was right is: all three, about equally. The one game the three venues did not
agree a favorite on was Wyoming at Central Michigan (Kalshi 50.50% home, DraftKings 49.57%, Polymarket
48.50%); the home team won 24-10, which decides nothing either.

Files: `results.py`, `results.csv`, `results-output.txt`, `scoring.py`, `scoring-output.txt`. The scoring
script refuses to run unless `games.csv` and `results.csv` hold the same 81 games, which is the check that
the sample did not move.

```
python3 scoring.py --games games.csv --results results.csv | diff - scoring-output.txt
python3 results.py --games games.csv --capture capture.json --out fresh-results.csv   # re-reads ESPN
```

`results.py` is safe to re-run: the games are final, so it writes the same rows with a new `read_at`.

## Spreads and totals (added 2026-09-18, issue 0xinsider/0xinsider#14901)

- https://0xinsider.com/research/polymarket-spreads-totals-vs-draftkings

A second capture, 17:35:31 to 17:35:36 UTC the same day, of Polymarket's spread and total ladders and the
DraftKings spread, total and price on each side from ESPN's scoreboard. NFL, college football and MLB.

| Measure | Spreads | Totals |
|---|---|---|
| Games on both venues | 31 | 41 |
| Polymarket's even line is the DraftKings number | 26 | 27 |
| Within half a point / one point | 29 / 29 | 32 / 39 |
| Median price gap at the DraftKings number | 0.58 pts | 0.50 pts |
| DraftKings overround, median | 4.71 pts | 4.75 pts |
| Polymarket even line, both sides at the ask plus the taker fee | 3.50 cents | 3.50 cents |

The even line held 67.9% of spread and total volume and the lines one point either side another 25.7%. Three
or more points away there were 914 quoted lines with a median book 4 cents wide; 25.1% had ever traded.

The unit is the game: every line on a ladder settles on one final score. The even line is the line priced
nearest 50 cents among lines with a book 5 cents wide or tighter and a price from 40 to 60 cents; a game with
no such line is left out, which is most of college football a day before kickoff.

Files: `spread-total-capture.py`, `spread-total-capture.json`, `spread-total-analysis.py`,
`spread-total-analysis-output.txt`, `spread-total-games.csv`. The two scripts load `capture.py` and
`analysis.py` from this directory for the ESPN reader, the team matching and the odds arithmetic.

```
python3 spread-total-analysis.py spread-total-capture.json | diff - spread-total-analysis-output.txt
```
