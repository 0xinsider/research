# Do wallet grades predict Polymarket outcomes?

79,580 large buys, each graded as of the trade, checked against settlement.

Corrected run against production on **2026-10-07** (headline export 13:39 UTC). Window 2026-06-01 to
2026-10-06. Published at https://0xinsider.com/research/do-wallet-grades-predict-outcomes.

## Correction, 2026-10-07

The first version of this study, run on 2026-09-12, reported that wallets graded S, A or B beat the
price they paid by 1.57 points (bootstrap interval +0.32 to +2.82) and that D and F wallets lost
2.06. Both numbers were wrong, and so was the claim that B wallets beat the price.

Its query took each buy's grade from the latest `trader_rankings` row dated on or before the trade
day. 0xinsider updates a wallet's latest ranking row in place when it recomputes the grade and sets
`computed_at = NOW()`, so that row could carry a grade decided after the trade, partly by the trades
being scored. Re-run on 2026-10-07, 99.3% of the S, A and B buys it scored used a row last written
after the trade (`results.md`, query 2). It also scored 318 buys on void or unresolved markets as
losses.

The rewrites moved winners up. 1,190 buys the September lookup counted as S, A or B came from
wallets that were D or F at the trade; those beat the price by 8.89 points. 852 buys it counted as
D or F came from wallets that were S, A or B at the trade; those lost 15.06 (`results.md`, query 3).

The same window, graded at the trade (`results.md`, query 1):

| Grade | Published 2026-09-12 | Graded at the trade | Buys |
|---|---:|---:|---:|
| S, A and B | +1.57 | +0.34 ± 1.07 | 28,963 |
| S | +1.32 | +1.54 ± 1.49 | 12,105 |
| A | +1.53 | +0.54 ± 1.79 | 5,816 |
| B | +1.94 | -1.09 ± 1.62 | 11,042 |
| D and F | -2.06 | -0.37 ± 1.34 | 21,007 |

S, A and B together show no measurable edge. The September files are kept, unchanged, in
`2026-09-12-superseded/`.

## Why win rate is the wrong measure

A wallet that only buys at 85c wins about 85% of the time and has learned nothing. Win rate
measures which prices someone likes, not whether they are right. The measure that survives is the
gap between how often the side won and the price paid for it. That gap is what a grade has to
predict.

## Method

Universe: every Polymarket buy of $10,000 or more from 2026-06-01 to 2026-10-06, at a price between
2c and 98c, on a market with a yes-or-no result (`winning_outcome IN (0, 1)`) recorded after the
trade. Buys only.

Grade at the trade:

- From 2026-09-20 04:46 UTC, when the baseline of 0xinsider's grade history completed, the grade the
  wallet showed when the order filled (`grade_forward_at`, `known = true`). A buy the history cannot
  prove (113 of 6,915 in that window) falls back to the ranking row below.
- Before that, the latest `trader_rankings` row dated on or before the trade day **and** last
  written at or before the trade (`computed_at <= traded_at`). Every current grade writer moves
  `computed_at`, so such a row held the same grade at the trade. Dropping that bound brings the
  look-ahead back.

A wallet whose only ranking row was rewritten after its trades has no row written before them, so
its buys count as ungraded.

The window starts on 2026-06-01 because grade coverage widened that month, from a few hundred
wallets scored per day in May to about 18,500 in June.

Intervals: 1.96 cluster-robust standard errors of the edge, computed once clustering by market and
once by wallet; the wider is reported. Buys on the same market, or from the same wallet, are not
independent.

## Result

Graded at the trade, letter by letter:

| Grade | Buys | Wallets | Won | Price paid | Edge | 95% interval |
|---|---:|---:|---:|---:|---:|---|
| S | 14,048 | 167 | 69.24% | 67.51c | **+1.73** | +0.41 to +3.06 |
| A | 7,167 | 532 | 66.25% | 65.13c | +1.12 | -0.44 to +2.67 |
| B | 12,254 | 1,190 | 60.21% | 61.12c | -0.91 | -2.39 to +0.56 |
| C | 10,083 | 1,407 | 61.52% | 61.63c | -0.12 | -2.13 to +1.89 |
| D | 3,235 | 652 | 57.47% | 61.60c | -4.14 | -7.34 to -0.93 |
| F | 21,926 | 1,390 | 58.14% | 57.99c | +0.15 | -1.05 to +1.35 |
| No grade | 10,867 | 2,133 | 58.47% | 57.14c | +1.34 | -1.40 to +4.07 |

Pooled: S and A +1.52 (+0.43 to +2.62) on 21,215 buys; S, A and B +0.63 (-0.32 to +1.58); D and F
-0.40 (-1.58 to +0.78).

S clears zero. A sits above zero with an interval that crosses it. B sits below zero. Below A the
letters do not line up: D lost, F, C and the ungraded came out near the price.

B certifies a profitable settled record: positive realized P&L across at least 10 resolved
markets. This study finds no price edge behind it.

## Three designs

| Grade read | Buys from | S | A | B | Buys |
|---|---|---:|---:|---:|---:|
| At the trade (headline) | 2026-06-01 to 10-06 | +1.73 ± 1.32 | +1.12 ± 1.55 | -0.91 ± 1.48 | 79,580 |
| At the fill only | 2026-09-20 to 10-06 | +3.63 ± 3.07 | +3.42 ± 3.66 | -0.24 ± 4.60 | 6,802 |
| At month start, next 30 days | Jul 1, Aug 1, Sep 1 origins | +2.67 ± 1.57 | +2.60 ± 1.97 | -0.44 ± 1.78 | 47,439 |

The ranking rows alone, 2026-06-01 to 09-19: S +1.54 (+0.10 to +2.97), A +0.72, B -0.94, on 72,665
buys. S is above zero in every design and clears it in each. A is above zero in every design and
clears it at month start. B is below zero in every design.

## Favorites, and categories

By price paid, S and A came in above the price in every band (+3.00 under 20c, +0.46 at 20-40c,
+1.47 at 40-60c, +1.67 at 60-80c, +1.63 at 80c and up); only the top band clears zero on its own,
± 1.38. B came in below the price in every band from 20c up.

S and A by category, 500 or more buys: soccer +1.42 on 11,419, tennis +0.27 on 2,731, esports
+3.92 on 2,205, baseball -0.18 on 1,922, NFL +1.98 on 1,000, politics +6.06 on 642, college
football +3.48 on 518. Soccer is 53.8% of the S and A buys. Esports clears zero (± 2.17), politics
narrowly (± 5.40).

## What this does not show

The edge is measured at each buy's own price against settlement. It ignores fees and slippage and
treats every position as held to resolution. Grades come from a wallet's own earlier settled trades,
so this is point-in-time, not a held-out universe. Only settled markets are in the sample. The
at-the-fill design covers 17 days.

1.73 points for S is a small edge. Nobody should read this as a reason to copy a trade.

## Reproduce it

- `queries.sql`: the exact SQL of this run. Queries 1 to 3 aggregate on the server. Queries 4 and 5
  export per-(grade, wallet, market) sums.
- `aggregate.py`: pools the exports into every table in `results.md` and writes `cluster_stats.csv`.
  The exports carry internal wallet ids and are not committed.
- `cluster_stats.csv` and `intervals.py`: the sums each interval is built from. `python3
  intervals.py` recomputes every interval in `results.md` from them with no database access.
- `results.md`: raw output of this run.

The sample grows as markets settle, so a re-run lands on more buys.
