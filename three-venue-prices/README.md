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

No game had been played at the capture, so this measures agreement between prices. It makes no claim
about which venue is more accurate. No Kalshi trading fee is modelled.

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
