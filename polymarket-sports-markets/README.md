# Polymarket sports markets: twelve studies

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

Series 3 (issue 0xinsider/0xinsider#13713):

- https://0xinsider.com/research/soccer-draws-polymarket (run 18:32 UTC). 17,953 settled Polymarket soccer
  draw markets since 2024-08-24 drew 25.9% (+/- 0.64); Premier League 26.2% of 770, Champions League 18.4%
  of 484, Argentina 31.0% of 500. All 10,057 complete three-market matches since April 2 resolved exactly
  one Yes. Large buys: draw Yes +4.00 [-3.48, +11.24], team-to-win No +3.25 [-0.91, +7.06]; nothing clears
  zero. Files: `soccer-draws.sql`, `soccer-draws-output.txt`, `soccer-draws-market-edge.csv`,
  `soccer-draws-bootstrap-output.txt`.
- https://0xinsider.com/research/cashing-out-polymarket-sports (run 18:24 UTC). 38,578 large sells: exit
  64.0c, sold outcome won 64.2%, exit edge -0.21 [-1.49, +1.01]. The query and export report the opposite
  sign (won minus price). Pre-kickoff 80c+ sells +6.15 [+0.26, +12.70]; pre-kickoff under 20c -12.29
  [-23.20, -1.63]; the 10-20c band is World Cup futures, Spain above all. Files: `cash-out.sql`,
  `cash-out-output.txt`, `cash-out-market-edge.csv`, `cash-out-bootstrap-output.txt`.

Series 4 (issue 0xinsider/0xinsider#13718):

- https://0xinsider.com/research/both-teams-to-score-polymarket (run 19:41 UTC). 13,071 settled both teams
  to score markets since 2025-10-24: 54.4% Yes (+/- 0.85); MLS 63.4% of 382, Bundesliga 62.9%, Premier
  League 56.6%, Serie A 46.6%, Argentina 44.6%. Over 2.5 hit 77.9% when both teams scored and 22.4% when
  not (12,704 matches). Draw 34.4% when both scored, 15.5% when not. Level at halftime 43.1% of 5,741; all
  4,435 complete halftime sets resolved exactly one Yes (level 41.8%, home ahead 32.7%, away 25.4%). A
  halftime leader won 75.4% of 3,530. Large buys: Yes +2.91 [-7.12, +12.43], No -0.49 [-10.71, +8.83].
  Side markets live under `<match slug>-more-markets` and `<match slug>-halftime-result`. Files:
  `btts-halftime.sql`, `btts-halftime-output.txt`, `btts-market-edge.csv`, `btts-bootstrap-output.txt`.
- https://0xinsider.com/research/tennis-first-set-winner-polymarket (run 19:46 UTC). 12,640 settled
  singles matches since 2025-11-09 with a first-set market: the first-set winner won 80.7% (+/- 0.69);
  ITF 83.1%, WTA 81.1%, ATP best of three 80.0%, best of five 74.3% (522). Best-of-three Total Sets O/U 2.5
  went Over 36.9% of 12,087. In 1,148 deciders the set-1 winner won 46.1% (+/- 2.88). Best of five is
  flagged from the listing (Set 4/5 markets, -2.5 set handicap, Total Sets 3.5/4.5, games total 30+);
  query 7 lists the tournaments behind it. A title is not a format flag: Australian Open qualifying is
  filed under "Australian Open Men's". Files: `tennis-sets.sql`, `tennis-sets-output.txt`.

Series 5 (issue 0xinsider/0xinsider#13754):

- https://0xinsider.com/research/point-spreads-polymarket (run 20:45 UTC). 79,769 settled spread markets
  titled "Spread: <team> (-X.5)" on 23,765 games; outcome 0 is the named team covering (17,571 of 17,571
  covered teams also won their moneyline). Polymarket lists ladders of lines for both teams, so no favorite
  is assumed. Large buys April 2 to September 13 (30,158, $565.9M): laying the points +4.68 [+0.25, +9.12],
  taking -2.82 [-6.84, +1.28]; NBA laying +5.32, taking -5.41; in-play laying +6.00 [+2.01, +9.93]. Games
  listing both teams at -1.5: MLB one-run games 29.1% of 1,882; soccer 7,528 matches drew 25.7%, were won by
  one goal 38.6%, two 20.2%, three or more 15.6%. Files: `spreads.sql`, `spreads-output.txt`,
  `spreads-market-edge.csv`, `spreads-bootstrap-output.txt`.

Series 6 (issue 0xinsider/0xinsider#13781):

- https://0xinsider.com/research/home-field-advantage-polymarket (run 21:44 UTC). Home team from Polymarket's
  event data: US leagues title games "<away> vs. <home>" (Gamma `teams[].ordering` agreed on 281 of 300
  sampled games, 19 unmarked), soccer names the home team first in the draw market (200 of 200). Home win
  rate: NBA 55.2% (2,770 games), NHL 54.2%, WNBA 54.4%, MLB 53.4% (4,778), NFL 52.1% +/- 3.74 (687),
  college football 64.7%. Club soccer, 13,327 matches: home 43.6%, draw 26.2%, away 30.2%; national-team
  matches, friendlies and one-match super cups excluded by series title (`soccer-prefix-series.tsv`).
  Pricing, 104,703 large buys from April 2: home -0.28 [-3.59, +3.00], away -0.66 [-3.94, +2.83]; home
  underdogs +1.05 [-3.53, +5.44]. Files: `home-advantage.sql`, `home-advantage-output.txt`,
  `home-advantage-market-edge.csv`, `home-advantage-bootstrap-output.txt`, `home-ordering.py`,
  `home-ordering-sample.tsv`, `home-ordering-output.txt`, `soccer-prefix-series.tsv`.

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
