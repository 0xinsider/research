# Polymarket sports markets: three studies

Published 2026-09-12 on the site (issue 0xinsider/0xinsider#13181, PR #13183):

- https://0xinsider.com/research/favorite-longshot-bias-polymarket-sports
- https://0xinsider.com/research/sharp-money-polymarket-sports
- https://0xinsider.com/research/when-large-sports-bets-land

One dataset: every `whale_alerts` buy of $1,000 or more on a sports-category Polymarket
market, joined to `market_outcomes` with `resolved_at > traded_at`, price 2c to 98c.
Read-only runs against production, 03:27 to 03:29 UTC.

## Headlines

| Study | Sample | Finding |
|---|---:|---|
| Calibration (Apr 2 to Sep 11) | 411,770 buys, $8.21B | Paid 60.6c, won 60.7%, +0.02 pts. Only under-10c clears zero: -3.52 pts [-5.50, -0.28], -60.6% on the dollar. Non-sports large buys miss by 6 to 10 pts in most buckets. |
| Sharp money (Jun 1 to Sep 11) | 155,832 buys, $2.50B | S/A/B +1.25 pts [+0.20, +2.31]; D/F -1.21 [-2.72, +0.33]. Holds in all 5 price buckets and 4 market types. Pre-kickoff +0.27 vs -0.52; in-play +1.95 vs -2.56. |
| Timing (Apr 2 to Sep 11) | 396,830 buys, $7.89B | 48.6% in-play. 1-7d early -3.21 pts [-5.09, -1.35]; 6h out through in-play calibrated. S/A/B 51% in-play vs D/F 37%; first hour of play +3.07 vs -3.03. |

## Window traps

- **Start 2026-04-02.** Before that day `whale_alerts.outcome_index` was a defaulted 0 for a
  large share of buys (80c+ buys tagged outcome 0 "won" 53 to 56% in Feb and Mar; outcome 1
  won 84 to 89%; both about 88% from April 2). Filed as #13182. An early pass read a 25-point
  reverse favorite-longshot bias that was this defect.
- Grades from 2026-06-01 (coverage widened that month). Alert floor $1,000 through July,
  $10,000 from August. Book quotes end 2026-07-31.
- The 10-20c bucket's +27.6% return is one market: Spain to win the World Cup at 15.2c,
  490 buys, +$41.31M against a bucket total of +$25.89M. Market-clustered intervals catch it.
- MMA 70c+ (-19 pts) is mostly Strickland vs Chimaev and Gaethje vs Topuria.

## Files

`calibration.sql`, `sharp-money.sql`, `timing.sql` with their `-output.txt`;
`bootstrap.py` (numpy, 5,000 draws, seed 20260912) and `bootstrap-output.txt`. The `\copy`
lines write the market-level CSVs the bootstrap reads.
