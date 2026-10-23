# Do wallet grades predict Polymarket outcomes?

81,855 large sports and esports buys, each graded as of the trade, checked against settlement.

Run against production on **2026-10-23** (headline export 13:43 UTC). Window 2026-06-01 to
2026-10-22. Published at https://0xinsider.com/research/do-wallet-grades-predict-outcomes.

## Why this run exists

0xinsider grades wallets on sports and esports markets only since 2026-10-22 11:32 UTC (migration
4390 in the product repository). This study scores the grade on the markets the grade now covers, so
its universe is sports and esports buys only. The 2026-10-07 run scored every market; it is kept,
unchanged apart from a note, in `2026-10-07-all-markets/`.

The basis, stated plainly: each buy carries the grade the wallet showed at the trade, and nearly
every buy in this window came before the switch, so it carries the grade of its time, computed on
every market. Recomputing older grades on the new basis would read trades the wallet made later,
which is the look-ahead the 2026-10-07 correction removed. From the switch to the end of the
window, 197 buys qualified, 77 of them from S, A or B wallets (`results.md`, post-switch count):
too few to read. The new-basis grade gets its own test once enough of its buys settle.

## Correction, 2026-10-07

The first version of this study, run on 2026-09-12, read each buy's grade from a ranking row that
0xinsider could rewrite after the trade, partly from the trades being scored. It reported that
wallets graded S, A or B beat the price by 1.57 points; graded at the trade, the same window came
to +0.34 ± 1.07. `2026-10-07-all-markets/README.md` has the evidence and the measurement
(`2026-10-07-all-markets/queries.sql`, queries 2 and 3). The September files are kept in
`2026-09-12-superseded/`. Every query here grades at the trade.

## Why win rate is the wrong measure

A wallet that only buys at 85c wins about 85% of the time and has learned nothing. Win rate
measures which prices someone likes, not whether they are right. The measure that survives is the
gap between how often the side won and the price paid for it. That gap is what a grade has to
predict.

## Method

Universe: every Polymarket buy of $10,000 or more from 2026-06-01 to 2026-10-22, at a price between
2c and 98c, on a sports or esports market with a yes-or-no result (`winning_outcome IN (0, 1)`)
recorded after the trade. Buys only.

A market counts as sports or esports by the rule the grade itself uses since 2026-10-22,
`is_provider_sports_market(provider_game_id, sports_market_type, category)` on `market_canonical`:
a provider game id, a sports market type, or a sports or esports category.

Grade at the trade:

- From 2026-09-20 04:46 UTC, when the baseline of 0xinsider's grade history completed, the grade the
  wallet showed when the order filled (`grade_forward_at`, `known = true`). A buy the history cannot
  prove (175 of 12,802 in that window) falls back to the ranking row below.
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
| S | 15,195 | 166 | 68.24% | 66.46c | **+1.78** | +0.54 to +3.02 |
| A | 7,353 | 502 | 64.55% | 63.91c | +0.64 | -0.88 to +2.16 |
| B | 12,295 | 1,070 | 59.10% | 60.02c | -0.92 | -2.39 to +0.55 |
| C | 9,836 | 1,251 | 60.99% | 60.87c | +0.12 | -1.81 to +2.06 |
| D | 3,424 | 616 | 56.51% | 60.38c | -3.87 | -6.91 to -0.82 |
| F | 23,326 | 1,368 | 57.54% | 57.64c | -0.10 | -1.24 to +1.03 |
| No grade | 10,426 | 1,801 | 58.53% | 55.83c | +2.70 | +0.22 to +5.18 |

81,855 buys from 3,834 wallets on 15,779 settled markets, $2.51B notional. Pooled: S and A +1.41
(+0.37 to +2.45) on 22,548 buys; S, A and B +0.59 (-0.32 to +1.49); D and F -0.58 (-1.65 to +0.49).

S clears zero. A sits above zero with an interval that crosses it. B sits below zero. Below A the
letters do not line up: D lost, C and F came out near the price, and the ungraded wallets beat it,
with an interval that clears zero.

B certifies a profitable settled record: positive realized P&L across at least 10 resolved
markets. This study finds no price edge behind it.

## Three designs

| Grade read | Buys from | S | A | B | Buys |
|---|---|---:|---:|---:|---:|
| At the trade (headline) | 2026-06-01 to 10-22 | +1.78 ± 1.24 | +0.64 ± 1.52 | -0.92 ± 1.47 | 81,855 |
| At the fill only | 2026-09-20 to 10-22 | +3.02 ± 1.87 | +1.74 ± 2.74 | -0.09 ± 4.38 | 12,627 |
| At month start, next 30 days | Jul 1, Aug 1, Sep 1 origins | +2.59 ± 1.60 | +2.00 ± 2.11 | -0.48 ± 1.85 | 45,222 |

The ranking rows alone, 2026-06-01 to 09-19: S +1.50 (+0.03 to +2.98), A +0.24, B -1.02, on 69,053
buys. S is above zero in every design and clears it in each. A is above zero in every design, but
its interval reaches zero in each. B is below zero in every design.

## Favorites, and categories

By price paid, S and A came in above the price in every band (+1.87 under 20c, +0.71 at 20-40c,
+1.66 at 40-60c, +1.41 at 60-80c, +1.28 at 80c and up). No band clears zero on its own; the
narrowest, 80c and up, is ± 1.40. B came in below the price in every band from 20c up.

S and A by category, 500 or more buys: soccer +1.50 on 11,984, tennis +0.58 on 3,087, esports
+3.44 on 2,513, baseball +0.11 on 1,980, NFL +1.88 on 1,445, college football +3.38 on 847. Soccer
is 53.1% of the S and A buys. Esports clears zero (± 2.04); no other category does.

## What this does not show

The edge is measured at each buy's own price against settlement. It ignores fees and slippage and
treats every position as held to resolution. Grades come from a wallet's own earlier settled trades,
so this is point-in-time, not a held-out universe. Only settled markets are in the sample. The
at-the-fill design covers 33 days.

It does not test the sports-and-esports grade itself: nearly every buy here carries the grade of
its time, computed on every market (see "Why this run exists").

1.78 points for S is a small edge. Nobody should read this as a reason to copy a trade.

## Reproduce it

- `queries.sql`: the exact SQL of this run. Query 4 exports per-(grade, wallet, market) sums for
  the headline, query 5 for month start, and query 6 counts the buys after the basis switch.
- `aggregate.py`: pools the exports into every table in `results.md` and writes `cluster_stats.csv`.
  The exports carry internal wallet ids and are not committed. This run:

  ```
  python3 aggregate.py export_2026-06-01_2026-07-25.csv export_2026-07-25_2026-09-20.csv \
      export_2026-09-20_2026-10-23.csv month_start.csv
  ```

- `cluster_stats.csv` and `intervals.py`: the sums each interval is built from. `python3
  intervals.py` recomputes every interval in `results.md` from them with no database access.
- `results.md`: raw output of this run.

The sample grows as markets settle, so a re-run lands on more buys.
