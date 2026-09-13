# 0xinsider research

The SQL, the raw query output and the bootstrap scripts behind the studies
published at [0xinsider.com/research](https://0xinsider.com/research).

Every figure on those pages comes from a run committed here. If a number on the
site does not match a number in this repository, the repository is right and the
page has a bug worth an issue.

## The studies

### [grade-vs-price](grade-vs-price) — do wallet grades predict outcomes?

67,531 Polymarket buys of $10,000 or more between 2026-06-01 and 2026-09-11, each
scored against the settled outcome using the grade the wallet already held on the
day it traded.

| Cohort | Trades | Markets | Won | Price paid | Edge | 95% CI |
|---|---:|---:|---:|---:|---:|---|
| S/A/B | 24,610 | 5,946 | 66.5% | 65.0c | **+1.57 pts** | [+0.32, +2.82] |
| C | 9,223 | 1,986 | 61.8% | 61.3c | +0.53 pts | [-1.93, +2.81] |
| D/F | 17,106 | 4,476 | 56.6% | 58.7c | **-2.06 pts** | [-3.61, -0.45] |
| No grade | 16,592 | 5,250 | 59.2% | 59.3c | -0.13 pts | [-1.81, +1.57] |

Published: <https://0xinsider.com/research/do-wallet-grades-predict-outcomes>

### [polymarket-sports-markets](polymarket-sports-markets) — ten studies on sports

411,770 sports buys of $1,000 or more between 2026-04-02 and 2026-09-11, $8.21B.

- **Calibration.** Average price paid 60.6c, the side bought won 60.7% of the
  time. The market is off by 0.02 points. Only the under-10c bucket clears zero,
  at -3.52 points and -60.6% on the dollar. Non-sports buys over the same window
  miss by 6 to 10 points in most buckets.
  <https://0xinsider.com/research/favorite-longshot-bias-polymarket-sports>
- **Sharp money.** S/A/B +1.25 pts [+0.20, +2.31] against D/F -1.21
  [-2.72, +0.33], holding in all five price buckets and four market types. The
  gap is an in-play gap: +1.95 against -2.56 after the start, +0.27 against -0.52
  before it. <https://0xinsider.com/research/sharp-money-polymarket-sports>
- **Timing.** 48.6% of large sports buys land after the start. Bought 1 to 7 days
  early, they lose 3.21 points [-5.09, -1.35]; from 6 hours out through in-play
  they are calibrated.
  <https://0xinsider.com/research/when-large-sports-bets-land>

The later sports studies (the wallet census, fading the crowd, over/under totals, soccer draws, cashing
out, both teams to score and the first set in tennis) are listed with their files in the directory's
README.

## Reproducing

Each study directory holds its SQL, the raw `psql` output of the run the figures
come from, and a market-clustered bootstrap.

```
cd grade-vs-price
psql "$DATABASE_URL" -X -f queries.sql          # the printed tables
python3 bootstrap.py                            # the confidence intervals
```

`grade-vs-price/market_edge.csv` is committed, so the bootstrap runs without
database access and reproduces the published intervals exactly:

```
cohort      trades  markets  edge_pts   95% CI
S/A/B        24610     5946      1.57   [+0.32, +2.82]
C             9223     1986      0.53   [-1.93, +2.81]
D/F          17106     4476     -2.06   [-3.61, -0.45]
no grade     16592     5250     -0.13   [-1.81, +1.57]
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

**Confidence intervals resample markets, not trades.** Four wallets buying the
same side of the same market are one observation, not four, and treating them as
four is how a result gets manufactured. 5,000 draws, seed 20260912.

**Grades are point-in-time.** Each trade takes the most recent grade dated on or
before the day of the trade. A grade computed after a market settled never
touches the trade it would have predicted.

## Things that will bite you

These are in the per-study READMEs too, because each one already produced a wrong
answer once.

- **The sample grows.** Every trade sits on a market that has settled, so the
  universe widens as open markets resolve. Three runs of the unchanged grade
  query ninety minutes apart returned 67,516, 67,517 and 67,531 trades. Bounding
  on `resolved_at` does not freeze it: rows gain an outcome after the fact
  carrying a timestamp that predates the bound. Pin a run timestamp and say so.
  The conclusions held across all three runs.
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
