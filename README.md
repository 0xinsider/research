# 0xinsider research

The SQL, the raw query output and the bootstrap scripts behind the studies
published at [0xinsider.com/research](https://0xinsider.com/research).

Every figure on those pages comes from a run committed here. If a number on the
site does not match a number in this repository, the repository is right and the
page has a bug worth an issue.

## The studies

### [grade-vs-price](grade-vs-price) — do wallet grades predict outcomes?

79,580 Polymarket buys of $10,000 or more between 2026-06-01 and 2026-10-06, each
scored against the settled outcome using the grade the wallet held at the trade.
Run 2026-10-07.

| Grade | Buys | Won | Price paid | Edge | 95% interval |
|---|---:|---:|---:|---:|---|
| S | 14,048 | 69.24% | 67.51c | **+1.73 pts** | +0.41 to +3.06 |
| A | 7,167 | 66.25% | 65.13c | +1.12 pts | -0.44 to +2.67 |
| B | 12,254 | 60.21% | 61.12c | -0.91 pts | -2.39 to +0.56 |
| D and F | 25,161 | 58.05% | 58.45c | -0.40 pts | -1.58 to +0.78 |

**Corrected 2026-10-07.** The 2026-09-12 run reported S/A/B +1.57 [+0.32, +2.82]. Its
query took the ranking row dated on or before the trade day, which the backend
updates in place after the trade; 99.3% of the S, A and B buys it scored used a row
last written after the trade. On the same window, graded at the trade, S/A/B comes
to +0.34 ± 1.07. The September files are in `grade-vs-price/2026-09-12-superseded/`.

Published: <https://0xinsider.com/research/do-wallet-grades-predict-outcomes>

### [polymarket-sports-markets](polymarket-sports-markets) — fifteen studies on sports

411,770 sports buys of $1,000 or more between 2026-04-02 and 2026-09-11, $8.21B.

- **Calibration.** Average price paid 60.6c, the side bought won 60.7% of the
  time. The market is off by 0.02 points. Only the under-10c bucket clears zero,
  at -3.52 points and -60.6% on the dollar. Non-sports buys over the same window
  miss by 6 to 10 points in most buckets.
  <https://0xinsider.com/research/favorite-longshot-bias-polymarket-sports>
- **Sharp money.** (The grade cohorts here use the lookup grade-vs-price corrected
  on 2026-10-07 and are being re-measured at the trade; measured that day, sports
  S/A/B comes to +0.50 graded at the trade, a point estimate.) S/A/B +1.25 pts [+0.20, +2.31] against D/F -1.21
  [-2.72, +0.33], holding in all five price buckets and four market types. The
  gap is an in-play gap: +1.95 against -2.56 after the start, +0.27 against -0.52
  before it. <https://0xinsider.com/research/sharp-money-polymarket-sports>
- **Timing.** 48.6% of large sports buys land after the start. Bought 1 to 7 days
  early, they lose 3.21 points [-5.09, -1.35]; from 6 hours out through in-play
  they are calibrated.
  <https://0xinsider.com/research/when-large-sports-bets-land>

The later sports studies (the wallet census, fading the crowd, over/under totals, soccer draws, cashing
out, both teams to score, the first set in tennis, point spreads, home advantage, NRFI, football
underdogs and esports first-map winners) are listed with their files in the directory's README.

### [three-venue-prices](three-venue-prices) — the same games on Polymarket, Kalshi and DraftKings

81 games priced on all three venues in one eight-second capture on 2026-09-18. Polymarket and Kalshi
showed the identical midpoint on 57 and never differed by more than 2 points. DraftKings' moneyline
with the margin removed sat a median of 0.99 points from Polymarket, and its overround was a median of
4.25 points against 3.16 cents for both sides on Polymarket with the taker fee. Public sources only:
`python3 analysis.py capture.json` reproduces every figure with no database.

All 81 have since been played and are scored against their results: Brier 0.1502 on Polymarket, 0.1504
on Kalshi and 0.1510 on DraftKings with its margin out, against 0.2414 for the sample's own home rate.
All three beat a no-information price by a wide margin and none is separable from the others -- every
pairwise interval spans zero on 81 games. `python3 scoring.py --games games.csv --results results.csv`
reproduces that too.

Published: <https://0xinsider.com/research/use-0xinsider-for-kalshi-draftkings>

## Reproducing

Each study directory holds its SQL, the raw `psql` output of the run the figures
come from, and a market-clustered bootstrap.

```
cd grade-vs-price
python3 intervals.py                            # every interval, no database
```

`grade-vs-price/cluster_stats.csv` holds the cluster sums each interval is built
from, so `intervals.py` reproduces every published interval without database
access. `aggregate.py` is the script that pooled the run's exports into those sums
and into `results.md`:

```
design|bucket|buys|edge_pts|ci_half|lo|hi
headline|S|14048|+1.73|1.32|+0.41|+3.06
headline|A|7167|+1.12|1.55|-0.44|+2.67
headline|B|12254|-0.91|1.48|-2.39|+0.56
```

The sports bootstrap takes the market-level CSVs the `\copy` lines in each
`.sql` file write, so it needs a database. `bootstrap-output.txt` is the run the
published figures come from.

You cannot run the SQL against our database. It reads internal tables through a
read-only role. The SQL is published so the method can be read and argued with,
and so anyone holding comparable Polymarket data can run the same test.

## What the numbers mean

**Edge** is the realized win rate minus the average price paid, in percentage
points. Buy at 65c and win 66.5% of the time and you are 1.5 points better than
the market that sold to you. Win rate alone measures which prices someone likes,
not whether they are right.

**Confidence intervals respect clustering.** Four wallets buying the same side of
the same market are one observation, not four, and treating them as four is how a
result gets manufactured. The sports studies resample markets (5,000 draws, seed
20260912). grade-vs-price reports cluster-robust intervals, computed once by
market and once by wallet, the wider shown.

**A grade is taken at the trade.** From 2026-09-20 the grade the wallet showed
when the order filled; before that, the latest ranking row dated on or before the
trade day and last written at or before the trade (`computed_at <= traded_at`).
The date on a ranking row is not when its grade was decided: the backend updates
a wallet's latest row in place, and a study that ignores `computed_at` scores
trades with grades written after them. grade-vs-price made that mistake until
2026-10-07; the sports studies still use that lookup and are being re-measured.

## Things that will bite you

These are in the per-study READMEs too, because each one already produced a wrong
answer once.

- **The sample grows.** Every trade sits on a market that has settled, so the
  universe widens as open markets resolve. Three runs of the unchanged grade
  query ninety minutes apart returned 67,516, 67,517 and 67,531 trades. Bounding
  on `resolved_at` does not freeze it: rows gain an outcome after the fact
  carrying a timestamp that predates the bound. Pin a run timestamp and say so.
  The conclusions held across all three runs.
- **A ranking row dated before a trade can be written after it.** Measured
  2026-10-07: for 99.3% of the S, A and B buys in the first grade-vs-price run,
  the ranking row the query used had been rewritten after the trade, and buys it
  counted as S, A or B from wallets that were D or F at the trade beat the price
  by 8.89 points. Bound on `computed_at`, or read the grade at the fill.
- **Grade coverage widened in June 2026**, from a few hundred wallets scored per
  day in May to about 18,500 in June. A window reaching further back reads "no
  grade" as a fact about the wallet when it is a fact about us. An earlier pass
  made that mistake and produced a meaningless -11.11 for March.
- **Sports data before 2026-04-02 is unusable for this.** The outcome index on
  large buys was a defaulted 0 for a large share of rows: 80c+ buys tagged
  outcome 0 "won" 53 to 56% in February and March while outcome 1 won 84 to 89%;
  from April 2 both are about 88%. An early pass read a 25-point reverse
  favorite-longshot bias that was this defect.
- **One market can carry a bucket.** The 10-20c sports bucket shows +27.6% on the
  dollar, and $41.31M of its $25.89M total is one market, Spain to win the World
  Cup at 15.2c. The market-clustered interval catches it: [-5.64, +19.10].

## Licence

[CC BY 4.0](LICENSE). Use it, quote it, check it, argue with it. A link back to
the study page is enough attribution.

Corrections are welcome as issues. Two number defects on the published pages were
caught in one day by checking prose against query output rather than by
proofreading, which is the check that works.
