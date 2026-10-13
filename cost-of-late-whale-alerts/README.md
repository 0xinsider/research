# What a late large-trade alert costs

Measured 2026-10-11 for the site (issue 0xinsider/0xinsider#23694) and added to this repository on
2026-10-13 (issue 0xinsider/0xinsider#24604):

- https://0xinsider.com/research/cost-of-late-whale-alerts

One dataset: every Polymarket large trade the 0xinsider feed recorded (`whale_alerts`) from 2026-09-10
00:00 to 2026-10-10 00:00 UTC, 30 days, 13,218 trades. No query filters on stake; the feed's floor in that
window was $10,000, or $1,000 on an earnings market (one such fill). Read-only runs against a production
read replica on 2026-10-11: queries A to D started between 14:06:33 and 14:06:55 UTC and query F at
14:18:46 UTC, at least 38 hours after the last fill.

0xinsider sells the live feed and shows the free one 24 hours late, so it is not neutral on this question.

## Headlines

| Measure | Result | From |
|---|---|---|
| Large sports trades whose market settled within 24 hours of the fill | 11,114 of 11,530 (96.4%) | query A |
| The same outside sports | 145 of 1,688 (8.6%); 1,057 had no result at the read | query A |
| Median hours from fill to settlement, tennis | 1.51 | query B |
| Seconds from the fill to the feed's record, trades from 2026-09-26 14:23 UTC | median 5.05 over 6,102 trades; 6,096 within 60 | query C |
| Buys priced 2c to 98c whose market was still open 24 hours after the fill | 1,588 of 12,351 buys: 404 sports, 1,184 other | query D |
| Price 24 hours after the fill minus price 5 minutes after it | mean +1.12c ± 0.80, median 0.00c, mean absolute 4.52c, on 1,585 buys | drift output |
| The same at 1 hour and at 6 hours | +0.20c ± 0.14 and +0.30c ± 0.27, on 1,588 buys | drift output |
| Dearer, cheaper and unchanged at 24 hours | 736, 540 and 309 | drift output |
| The large buy's fill minus the last price before it | median +0.50c, mean +1.37c | drift output |

Split by group, the 24-hour mean is +1.65c ± 1.70 on 402 sports buys and +0.94c ± 0.93 on 1,183 others.
The pooled interval and the non-sports one clear zero. The sports one does not.

## What settled means here

A market counts as settled when 0xinsider's `market_outcomes` holds a result. Its settle time is
Polymarket's where one is recorded and 0xinsider's own write time otherwise: 9,520 of the 13,218 trades,
9,006 of them on sports (query A, last column). A write time is at or after the settlement, so a share
settled within a cutoff is a lower bound and a median time to settle is an upper bound.

## Files

Each file keeps the name it was written under, so the names the files cite inside themselves resolve in
this directory.

- `2026-10-11-cost-of-late-whale-alerts-charts.sql.txt`: queries A to F. Query E returns the cohort.
- `2026-10-11-cost-of-late-whale-alerts-charts-output.txt`: the raw output of A to D and F.
- `2026-10-11-cost-of-late-whale-alerts-cohort.csv`: query E's 1,588 rows, one per buy, with the five
  prices the script measured for it: `price_before_fill`, `price_5m`, `price_1h`, `price_6h` and
  `price_24h`. An empty price is a buy with no price point in the 10 minutes before that mark; three
  buys have none at 24 hours.
- `2026-10-11-cost-of-late-whale-alerts-drift.py`: reads Polymarket's public price history for each buy
  and prints the report. Its usage line calls it `late_whale_drift.py`; it is this file.
- `2026-10-11-cost-of-late-whale-alerts-drift-output.txt`: that report, from the run of 2026-10-11.

One citation leaves the directory. The SQL takes its sports category list from the fade-the-crowd chart
queries and cites them by an earlier file name. Here that file is
`../polymarket-sports-markets/fade-crowd-charts-2026-10-11.sql`.

## Reproducing

The summary recomputes from the committed prices, with no database and no network:

```
cd cost-of-late-whale-alerts
sqlite3 :memory: -cmd '.mode csv' -cmd '.import 2026-10-11-cost-of-late-whale-alerts-cohort.csv t' \
  "select count(*), round(avg(100 * (price_24h - price_5m)), 2), round(avg(abs(100 * (price_24h - price_5m))), 2),
          sum(price_24h + 0 > price_5m + 0), sum(price_24h + 0 < price_5m + 0), sum(price_24h + 0 = price_5m + 0)
   from t where price_5m <> '' and price_24h <> ''"
1585,1.12,4.52,736,540,309
```

That line is the buys priced at both marks, the mean and the mean absolute move in cents, and the buys
that were dearer, cheaper and unchanged at 24 hours. The interval is clustered by outcome token and needs
the script.

The script reads the prices again from Polymarket, one request per buy, with no key. Standard library
only, Python 3.8 or later (`statistics.fmean`); the 2026-10-13 run below used 3.14:

```
python3 -I 2026-10-11-cost-of-late-whale-alerts-drift.py 2026-10-11-cost-of-late-whale-alerts-cohort.csv cache marks.csv > report.txt
tail -n +5 2026-10-11-cost-of-late-whale-alerts-drift-output.txt | diff - report.txt    # no output means it reproduces
```

It keeps each response in `cache/` and skips a buy it already holds. The responses of the 2026-10-11 run
were not kept, so a run today is a new read of the history Polymarket serves for those windows on that
day. A run on 2026-10-13 from 12:29 UTC returned the committed report line for line, and the same five
prices for all 1,588 buys. Polymarket decides how long it serves minute-level history, so a later run can
differ.

You cannot run the SQL against our database. It reads internal tables through a read-only role, and is
published so the method can be read and argued with.

## Definitions

The price at a mark is the last point of Polymarket's price history at or before the mark, and no more
than 10 minutes before it. The marks are the fill (the last point before it), then 5 minutes, 1 hour, 6
hours and 24 hours after the fill. The 5-minute mark stands in for a reader acting on a live alert, and the
24-hour mark is the delay of 0xinsider's free feed. The cost of waiting is the later price minus the
5-minute price, in cents per share of the outcome bought: positive means the later reader paid more. A buy
with no point inside the bound at a mark is counted as missing at that mark and never filled in. The ± is
the 95% half-width of the mean, clustered by outcome token.

## What the number leaves out

These are price-history points, before the spread, the fee and the reader's own size. Half of the 1,588
buys, 798, are in the Politics category and 404 are on sports, so the cent is a politics number more than
a sports one. A game
can also end before its market settles: buy 12264557, $261,863 of the Texans at 58 cents on 2026-09-19
(query F), read 0.35 cents at the 24-hour mark, 29 minutes before the market settled. That is a result,
not a drift.
