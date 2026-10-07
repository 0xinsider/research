# Raw output

One run of `psql -X -f queries.sql` against production through a read-only role, **2026-09-12T02:25:45Z**. Every figure in `README.md` and on the published page comes from this run.

The sample is not fixed. It requires `winning_outcome IS NOT NULL`, so it grows as open markets settle: three runs about ninety minutes apart on this day returned 67,516, 67,517 and 67,531 trades. The conclusions did not move. See the reproducibility section in `README.md`.

Query 6 emits one row per market and lands in `market_edge.csv` rather than here.

```
CREATE VIEW
CREATE VIEW
 trades | wallets | markets | notional_musd 
--------+---------+---------+---------------
  67531 |    4313 |   11370 |        2098.9
(1 row)

 grade  | trades | wallets | notional_musd | win_pct | implied_pct | edge_pts | dollar_roi_pct 
--------+--------+---------+---------------+---------+-------------+----------+----------------
 S      |  11230 |     133 |         318.9 |    69.7 |        68.4 |     1.32 |           0.60
 A      |   4984 |     400 |         129.0 |    67.6 |        66.0 |     1.53 |           4.02
 B      |   8396 |     941 |         269.4 |    61.8 |        59.8 |     1.94 |           3.27
 C      |   9223 |    1275 |         288.3 |    61.8 |        61.3 |     0.53 |           4.76
 D      |   2598 |     604 |         100.3 |    56.5 |        60.9 |    -4.32 |          -3.87
 F      |  14508 |    1180 |         419.9 |    56.7 |        58.3 |    -1.65 |           0.68
 (none) |  16592 |    2148 |         573.1 |    59.2 |        59.3 |    -0.13 |           1.54
(7 rows)

  cohort  | trades | wallets | markets | notional_musd | win_pct | implied_pct | edge_pts | dollar_roi_pct 
 C        |   9223 |    1275 |    1986 |         288.3 |    61.8 |        61.3 |     0.53 |           4.76
 D/F      |  17106 |    1557 |    4476 |         520.2 |    56.6 |        58.7 |    -2.06 |          -0.20
 S/A/B    |  24610 |    1207 |    5946 |         717.3 |    66.5 |        65.0 |     1.57 |           2.22
 no grade |  16592 |    2148 |    5250 |         573.1 |    59.2 |        59.3 |    -0.13 |           1.54
(4 rows)

    bucket    | cohort |  n   | edge_pts 
--------------+--------+------+----------
 a. under 20c | D/F    |  395 |     1.92
 a. under 20c | S/A/B  |  340 |     3.18
 b. 20-40c    | D/F    | 1897 |     0.01
 b. 20-40c    | S/A/B  | 2082 |     0.93
 c. 40-60c    | D/F    | 7589 |    -1.60
 c. 40-60c    | S/A/B  | 8169 |     0.42
 d. 60-80c    | D/F    | 4267 |    -1.93
 d. 60-80c    | S/A/B  | 6969 |     3.27
 e. 80c+      | D/F    | 2958 |    -5.27
 e. 80c+      | S/A/B  | 7050 |     1.35
(10 rows)

 category |   n   | edge_pts 
----------+-------+----------
 Politics |   593 |     6.94
 Esports  |  2185 |     2.85
 Soccer   | 15527 |     1.77
 Tennis   |  2692 |     0.44
 Baseball |  2557 |    -1.10
(5 rows)

(17658 rows)

 month_start | days | avg_wallets_scored_per_day 
-------------+------+----------------------------
 2026-02-01  |    4 |                          2
 2026-03-01  |   28 |                         23
 2026-04-01  |   29 |                         52
 2026-05-01  |   31 |                        238
 2026-06-01  |   30 |                      18464
 2026-07-01  |   31 |                      18580
 2026-08-01  |   31 |                       3757
 2026-09-01  |   12 |                       3912
(8 rows)

```

## Bootstrap

```
cohort      trades  markets  edge_pts   95% CI
S/A/B        24610     5946      1.57   [+0.32, +2.82]
C             9223     1986      0.53   [-1.93, +2.81]
D/F          17106     4476     -2.06   [-3.61, -0.45]
no grade     16592     5250     -0.13   [-1.81, +1.57]
```
