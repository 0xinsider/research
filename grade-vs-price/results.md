# Grade vs price paid: raw output, run of 2026-10-23

Every table below is the unedited output of `aggregate.py` (queries 4 and 5) or of `queries.sql`
(query 6), read-only against the production read replica. The exports ran between 13:42 and 13:45
UTC on 2026-10-23; query 6 ran at 14:01 UTC, from the committed text, and returned
197 buys, the count the page cites. Edge and interval columns are percentage points. `ci` is the 95% half-width,
the wider of the market and wallet clusterings. The 2026-10-07 all-market output is in
`2026-10-07-all-markets/results.md`, the September 12 output in `2026-09-12-superseded/results.md`.

The universe is sports and esports buys only (`queries.sql`, header).

## Queries 4 and 5, pooled by aggregate.py

`headline` is grade at the trade, 2026-06-01 to 2026-10-22. `ranking_rows_only` is its part before
2026-09-20. `exact_at_fill` is the buys from 2026-09-20 whose grade the history proves at the fill.
`month_start` pools the July 1, August 1 and September 1 origins, 30 days each.

```
== headline
bucket|trades|wallets|markets|notional_musd|won_pct|price_pct|edge|ci|lo|hi
S|15195|166|5656|422.1|68.24|66.46|+1.78|1.24|+0.54|+3.02
A|7353|502|3752|181.9|64.55|63.91|+0.64|1.52|-0.88|+2.16
B|12295|1070|4752|377.7|59.10|60.02|-0.92|1.47|-2.39|+0.55
C|9836|1251|2568|293.7|60.99|60.87|+0.12|1.93|-1.81|+2.06
D|3424|616|1318|107.1|56.51|60.38|-3.87|3.04|-6.91|-0.82
F|23326|1368|8061|641.4|57.54|57.64|-0.10|1.13|-1.24|+1.03
none|10426|1801|3004|486.4|58.53|55.83|+2.70|2.48|+0.22|+5.18
S/A|22548|563|7817|603.9|67.03|65.63|+1.41|1.04|+0.37|+2.45
S/A/B|34843|1343|10192|981.7|64.23|63.65|+0.59|0.91|-0.32|+1.49
D/F|26750|1704|8714|748.5|57.41|57.99|-0.58|1.07|-1.65|+0.49
all|81855|3834|15779|2510.3|60.89|60.47|+0.42|0.75|-0.33|+1.16

== ranking_rows_only
bucket|trades|wallets|markets|notional_musd|won_pct|price_pct|edge|ci|lo|hi
S|12286|126|4142|343.6|69.44|67.93|+1.50|1.47|+0.03|+2.98
A|5643|396|2778|138.6|64.82|64.58|+0.24|1.81|-1.57|+2.05
B|10956|959|4042|335.9|58.92|59.94|-1.02|1.58|-2.60|+0.56
C|9461|1169|2301|280.9|61.14|60.85|+0.28|1.99|-1.71|+2.27
D|2893|532|978|92.3|56.38|60.50|-4.13|3.42|-7.55|-0.70
F|18478|1192|5950|519.1|58.09|57.85|+0.24|1.34|-1.10|+1.58
none|9336|1628|2447|444.2|58.58|55.56|+3.02|2.71|+0.31|+5.72
S/A|17929|452|5748|482.3|67.98|66.88|+1.11|1.24|-0.14|+2.35
S/A/B|28885|1197|7774|818.2|64.55|64.25|+0.30|1.09|-0.79|+1.38
D/F|21371|1498|6473|611.4|57.85|58.21|-0.35|1.25|-1.60|+0.90
all|69053|3497|11981|2154.7|61.20|60.74|+0.46|0.85|-0.39|+1.32

== exact_at_fill
bucket|trades|wallets|markets|notional_musd|won_pct|price_pct|edge|ci|lo|hi
S|2902|82|1519|78.3|63.27|60.25|+3.02|1.87|+1.15|+4.88
A|1692|184|972|42.7|63.42|61.67|+1.74|2.74|-0.99|+4.48
B|1326|195|706|41.5|60.48|60.58|-0.09|4.38|-4.48|+4.29
C|373|99|265|12.7|57.37|61.28|-3.90|7.94|-11.84|+4.04
D|529|95|338|14.8|57.28|59.65|-2.38|6.08|-8.46|+3.70
F|4826|386|2112|121.9|55.49|56.86|-1.37|1.95|-3.32|+0.59
none|979|157|499|38.8|57.41|57.66|-0.25|5.27|-5.52|+5.02
S/A|4594|232|2070|121.0|63.32|60.77|+2.55|1.57|+0.97|+4.12
S/A/B|5920|374|2420|162.5|62.69|60.73|+1.96|1.53|+0.43|+3.49
D/F|5355|443|2242|136.7|55.67|57.13|-1.47|1.90|-3.37|+0.44
all|12627|858|3789|350.6|59.14|58.98|+0.16|1.26|-1.10|+1.42

== month_start
bucket|trades|wallets|markets|notional_musd|won_pct|price_pct|edge|ci|lo|hi
S|7814|84|3132|214.2|70.69|68.11|+2.59|1.60|+0.98|+4.19
A|3242|213|1914|76.1|67.24|65.25|+2.00|2.11|-0.12|+4.11
B|5096|376|2670|143.6|59.95|60.43|-0.48|1.85|-2.33|+1.37
C|6263|546|1654|179.7|63.18|62.57|+0.62|2.15|-1.53|+2.76
D|300|103|206|4.8|57.67|66.41|-8.74|7.67|-16.41|-1.07
F|14249|708|5318|364.9|56.99|57.60|-0.61|1.26|-1.87|+0.66
none|8258|1023|2824|330.8|59.08|57.36|+1.72|2.30|-0.58|+4.02
S/A|11056|277|4342|290.3|69.68|67.27|+2.41|1.34|+1.08|+3.75
S/A/B|16152|628|5849|434.0|66.61|65.11|+1.50|1.14|+0.36|+2.64
D/F|14549|800|5380|369.7|57.01|57.78|-0.77|1.31|-2.08|+0.53
all|45222|2674|9924|1314.1|61.67|60.98|+0.69|0.91|-0.22|+1.59

== headline by price band (S/A, B, D/F)
under 20c | S/A +1.87 +-10.77 (n=235) | B +3.09 +-13.11 (n=170) | D/F +4.29 +-15.85 (n=399)
20-40c | S/A +0.71 +-3.99 (n=1606) | B -1.49 +-5.60 (n=1313) | D/F -0.12 +-4.75 (n=2814)
40-60c | S/A +1.66 +-1.74 (n=7607) | B -0.98 +-2.19 (n=5277) | D/F -0.53 +-1.35 (n=13099)
60-80c | S/A +1.41 +-2.74 (n=6528) | B -0.43 +-3.50 (n=3266) | D/F -0.44 +-2.70 (n=6514)
80c and up | S/A +1.28 +-1.40 (n=6572) | B -1.48 +-3.34 (n=2269) | D/F -1.81 +-2.72 (n=3924)

== headline, S and A by category, 500 or more buys
Soccer|11984|+1.50|1.66|share 53.1%
Tennis|3087|+0.58|2.33|share 13.7%
Esports|2513|+3.44|2.04|share 11.1%
Baseball|1980|+0.11|2.86|share 8.8%
NFL|1445|+1.88|2.85|share 6.4%
NCAAF|847|+3.38|4.16|share 3.8%
```

## Query 6: buys after the basis switch

2026-10-22 11:32:04 UTC to the end of the window. The last row is the total.

```
    bk    | trades | wallets | markets | won_pct | price_pct |  edge  
----------+--------+---------+---------+---------+-----------+--------
 S/A      |     71 |      36 |      44 |   57.75 |     63.89 |  -6.15
 B        |      6 |       5 |       4 |   33.33 |     54.84 | -21.50
 C-F      |    100 |      43 |      47 |   59.00 |     52.64 |   6.36
 none     |     16 |       8 |       9 |   81.25 |     59.96 |  21.29
 unproven |      4 |       4 |       3 |   75.00 |     63.34 |  11.66
          |    197 |      94 |      81 |   59.90 |     57.58 |   2.32
(6 rows)
```

## intervals.py, from cluster_stats.csv

Every interval above, recomputed from the committed sums with no database access. It matches
`aggregate.py`'s output line for line.

```
design|bucket|buys|edge_pts|ci_half|lo|hi
headline|S|15195|+1.78|1.24|+0.54|+3.02
headline|A|7353|+0.64|1.52|-0.88|+2.16
headline|B|12295|-0.92|1.47|-2.39|+0.55
headline|C|9836|+0.12|1.93|-1.81|+2.06
headline|D|3424|-3.87|3.04|-6.91|-0.82
headline|F|23326|-0.10|1.13|-1.24|+1.03
headline|none|10426|+2.70|2.48|+0.22|+5.18
headline|S/A|22548|+1.41|1.04|+0.37|+2.45
headline|S/A/B|34843|+0.59|0.91|-0.32|+1.49
headline|D/F|26750|-0.58|1.07|-1.65|+0.49
headline|all|81855|+0.42|0.75|-0.33|+1.16
ranking_rows_only|S|12286|+1.50|1.47|+0.03|+2.98
ranking_rows_only|A|5643|+0.24|1.81|-1.57|+2.05
ranking_rows_only|B|10956|-1.02|1.58|-2.60|+0.56
ranking_rows_only|C|9461|+0.28|1.99|-1.71|+2.27
ranking_rows_only|D|2893|-4.13|3.42|-7.55|-0.70
ranking_rows_only|F|18478|+0.24|1.34|-1.10|+1.58
ranking_rows_only|none|9336|+3.02|2.71|+0.31|+5.72
ranking_rows_only|S/A|17929|+1.11|1.24|-0.14|+2.35
ranking_rows_only|S/A/B|28885|+0.30|1.09|-0.79|+1.38
ranking_rows_only|D/F|21371|-0.35|1.25|-1.60|+0.90
ranking_rows_only|all|69053|+0.46|0.85|-0.39|+1.32
exact_at_fill|S|2902|+3.02|1.87|+1.15|+4.88
exact_at_fill|A|1692|+1.74|2.74|-0.99|+4.48
exact_at_fill|B|1326|-0.09|4.38|-4.48|+4.29
exact_at_fill|C|373|-3.90|7.94|-11.84|+4.04
exact_at_fill|D|529|-2.38|6.08|-8.46|+3.70
exact_at_fill|F|4826|-1.37|1.95|-3.32|+0.59
exact_at_fill|none|979|-0.25|5.27|-5.52|+5.02
exact_at_fill|S/A|4594|+2.55|1.57|+0.97|+4.12
exact_at_fill|S/A/B|5920|+1.96|1.53|+0.43|+3.49
exact_at_fill|D/F|5355|-1.47|1.90|-3.37|+0.44
exact_at_fill|all|12627|+0.16|1.26|-1.10|+1.42
month_start|S|7814|+2.59|1.60|+0.98|+4.19
month_start|A|3242|+2.00|2.11|-0.12|+4.11
month_start|B|5096|-0.48|1.85|-2.33|+1.37
month_start|C|6263|+0.62|2.15|-1.53|+2.76
month_start|D|300|-8.74|7.67|-16.41|-1.07
month_start|F|14249|-0.61|1.26|-1.87|+0.66
month_start|none|8258|+1.72|2.30|-0.58|+4.02
month_start|S/A|11056|+2.41|1.34|+1.08|+3.75
month_start|S/A/B|16152|+1.50|1.14|+0.36|+2.64
month_start|D/F|14549|-0.77|1.31|-2.08|+0.53
month_start|all|45222|+0.69|0.91|-0.22|+1.59
headline_price_1|S/A|235|+1.87|10.77|-8.89|+12.64
headline_price_1|B|170|+3.09|13.11|-10.02|+16.20
headline_price_1|D/F|399|+4.29|15.85|-11.55|+20.14
headline_price_2|S/A|1606|+0.71|3.99|-3.28|+4.70
headline_price_2|B|1313|-1.49|5.60|-7.09|+4.12
headline_price_2|D/F|2814|-0.12|4.75|-4.87|+4.63
headline_price_3|S/A|7607|+1.66|1.74|-0.08|+3.40
headline_price_3|B|5277|-0.98|2.19|-3.16|+1.21
headline_price_3|D/F|13099|-0.53|1.35|-1.88|+0.81
headline_price_4|S/A|6528|+1.41|2.74|-1.33|+4.15
headline_price_4|B|3266|-0.43|3.50|-3.92|+3.07
headline_price_4|D/F|6514|-0.44|2.70|-3.14|+2.27
headline_price_5|S/A|6572|+1.28|1.40|-0.13|+2.68
headline_price_5|B|2269|-1.48|3.34|-4.82|+1.85
headline_price_5|D/F|3924|-1.81|2.72|-4.53|+0.91
headline_category|S/A Soccer|11984|+1.50|1.66|-0.16|+3.15
headline_category|S/A Tennis|3087|+0.58|2.33|-1.75|+2.90
headline_category|S/A Esports|2513|+3.44|2.04|+1.40|+5.48
headline_category|S/A Baseball|1980|+0.11|2.86|-2.75|+2.97
headline_category|S/A NFL|1445|+1.88|2.85|-0.97|+4.74
headline_category|S/A NCAAF|847|+3.38|4.16|-0.79|+7.54
```
