# Polymarket sports markets: six studies

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

## Series 2, published 2026-09-13 (issue 0xinsider/0xinsider#13662, PR #13664)

- https://0xinsider.com/research/how-many-polymarket-sports-bettors-are-profitable
- https://0xinsider.com/research/fading-the-crowd-polymarket-sports

| Study | Sample | Finding |
|---|---:|---|
| Wallet census (snapshot 2026-09-13 16:13 UTC) | 36,149 wallets with 20+ settled sports markets, $149.5M net | 48.8% in profit (half-width 0.52 pts), median -$8. Top 1% (362 wallets) hold $395.1M = 68% of gross profit; bottom 10% -$401.1M. Profitable half wins 64.1% at 55.2c (edge +6.15), the rest 49.1% at 53.0c (-1.13). By sport 48.1% (soccer) to 57.4% (cricket). |
| Fading the crowd (Jun 1 to Sep 12, pre-kickoff) | 71,543 buys, 7,966 markets, $1.42B | When 90%+ of D/F money sat on one side (844 markets), that side paid 67.3c and won 63.6%: -3.68 pts [-6.71, -0.69]; flat fade +16.4%, follow -6.0%. S/A/B 90%+ lean is priced in: -0.28 [-2.81, +2.34]. Crowd on a favorite -4.20 [-7.45, -1.05]; on an underdog -1.25 [-9.05, +6.71]. |

The census reads `trader_category_stats`, the per-wallet, per-category read model (one row per wallet
and canonical category with 5+ settled markets of $20+ at stake; `total_pnl_category` = realized P&L
summed). The fade study uses the sharp-money universe restricted to buys before `markets.game_start_time`
on a moneyline, child moneyline, spread or total; the side price is what the D/F buyers paid on the side
they leaned to, and the fade is priced at its complement (query 11 measures the half-cent gap to what the
other side's buyers actually paid).

Part 2 (issue 0xinsider/0xinsider#13691): https://0xinsider.com/research/over-under-polymarket-sports.
Game totals (`sports_market_type = 'totals'`, Over/Under), April 2 to September 13, run 16:51 UTC:
45,662 buys of $1,000+ on 7,120 markets, $810.0M, and 82,080 settled totals counted once. The Under
settled 52.7% (+/- 0.34 pts; soccer 54.3%, esports 55.3%, NBA 44.7%, MMA 37.8%); every lined total is
a half point. Under buyers paid 58.4c and won 57.9% (-0.50 [-3.17, +2.23]); Over buyers 56.4c, 55.8%
(-0.61 [-3.37, +2.21]). No sport, soccer line, phase or grade cohort clears zero (soccer Over -2.11
[-6.49, +2.36]; soccer 3.5 Over -4.92 [-15.97, +6.94]). S/A/B wallets put 60.5% of totals buys on the
Under (D/F 50.7%); S/A/B Under +2.12 [-2.78, +6.91]. Files: `over-under.sql`, `over-under-output.txt`,
`over-under-market-edge.csv` (32,916 rows), `over-under-bootstrap-output.txt`.

`fade-crowd-market-edge.csv` is committed (one row per market, 66-character condition ids, no
wallets), so `python3 bootstrap-2026-09-13.py fade-crowd-market-edge.csv` reproduces the intervals with
no database.

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

Series 2: `wallet-census.sql`, `fade-crowd.sql` with their `-output.txt`;
`fade-crowd-market-edge.csv`; `bootstrap-2026-09-13.py` (seed 20260913) and
`bootstrap-2026-09-13-output.txt`.
