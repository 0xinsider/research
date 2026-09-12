# Do wallet grades predict Polymarket outcomes?

67,531 large buys, checked against settlement.

One run against production at **2026-09-12T02:25:45Z**. Window 2026-06-01 to 2026-09-11.

## The question

0xinsider grades every Polymarket wallet S through F from its past record. The
grade is only worth anything if it says something about trades the wallet has
not made yet. So: take every large buy in the last three months, look up the
grade the wallet already held on the day it traded, and check the settled
outcome of the market.

## Why win rate is the wrong measure

A wallet that only buys at 85c wins about 85% of the time and has learned
nothing. Win rate measures which prices someone likes, not whether they are
right.

The measure that survives is the gap between how often the side won and the
price paid for it. Buy at 65c and win 66.5% of the time and you are 1.5 points
better than the market that sold to you. Buy at 58.7c and win 56.6% and you are
2.1 points worse. That gap is what a grade has to predict.

## Method

Universe: every buy of $10,000 or more on Polymarket between 2026-06-01 and
2026-09-11, on a market that settled after the trade, at a price between 2c and
98c. Buys only, because a buy at a price on a named outcome is a clean
directional bet. 67,531 trades, 4,313 wallets, 11,370 settled markets, $2.10B
notional.

Grade assignment is point-in-time. For each trade the query takes the most
recent `trader_rankings` row dated on or before the day of the trade. A grade
computed after the market settled never touches the trade it would have
predicted.

The window starts 2026-06-01 because grade coverage widened that month, from a
few hundred wallets scored per day in May to about 18,500 in June. Earlier than
that, "no grade" mostly means we had not scored anyone yet.

Confidence intervals are bootstrapped over markets rather than trades. Four
wallets buying the same side of the same market are not four independent
observations, and treating them as such is how you manufacture significance.
5,000 resamples, seed 20260912.

## Result

Grade cohorts, by the gap between realized win rate and price paid:

| Cohort | Trades | Wallets | Markets | Notional | Won | Price paid | Edge | 95% CI |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| S/A/B | 24,610 | 1,207 | 5,946 | $717.3M | 66.5% | 65.0% | **+1.57 pts** | [+0.32, +2.82] |
| C | 9,223 | 1,275 | 1,986 | $288.3M | 61.8% | 61.3% | +0.53 pts | [-1.93, +2.81] |
| D/F | 17,106 | 1,557 | 4,476 | $520.2M | 56.6% | 58.7% | **-2.06 pts** | [-3.61, -0.45] |
| No grade yet | 16,592 | 2,148 | 5,250 | $573.1M | 59.2% | 59.3% | -0.13 pts | [-1.81, +1.57] |

S, A and B wallets beat the price they paid. D and F wallets lost to it. Both
intervals clear zero. C wallets and wallets with no record yet are
indistinguishable from the market, which is the answer you would expect if the
grade were doing its job at the ends and nothing in the middle.

By individual grade:

| Grade | Trades | Wallets | Notional | Won | Price paid | Edge | Dollar ROI |
|---|---:|---:|---:|---:|---:|---:|---:|
| S | 11,230 | 133 | $318.9M | 69.7% | 68.4% | +1.32 | +0.60% |
| A | 4,984 | 400 | $129.0M | 67.6% | 66.0% | +1.53 | +4.02% |
| B | 8,396 | 941 | $269.4M | 61.8% | 59.8% | +1.94 | +3.27% |
| C | 9,223 | 1,275 | $288.3M | 61.8% | 61.3% | +0.53 | +4.76% |
| D | 2,598 | 604 | $100.3M | 56.5% | 60.9% | -4.32 | -3.87% |
| F | 14,508 | 1,180 | $419.9M | 56.7% | 58.3% | -1.65 | +0.68% |
| none | 16,592 | 2,148 | $573.1M | 59.2% | 59.3% | -0.13 | +1.54% |

The ordering inside S/A/B does not run the way the letters do. B posts the
largest edge and S the smallest, and F outperforms D. At these sample sizes
those differences sit inside the noise, so the honest reading is that the grade
separates the top three letters from the bottom two and does not finely rank
within them.

Dollar ROI and edge disagree for S, and the reason is size. S wallets put
$318.9M through 11,230 trades and concentrate it in fewer, larger positions, so
one settled market moves the dollar figure much more than it moves the per-trade
edge.

## The obvious objection

Good wallets might just buy favorites, and favorites win. Splitting by the price
paid answers it:

| Price paid | S/A/B edge | D/F edge |
|---|---:|---:|
| under 20c | +3.18 (n=340) | +1.92 (n=395) |
| 20c to 40c | +0.93 (n=2,082) | +0.01 (n=1,897) |
| 40c to 60c | +0.42 (n=8,169) | -1.60 (n=7,589) |
| 60c to 80c | +3.27 (n=6,969) | -1.93 (n=4,267) |
| 80c and up | +1.35 (n=7,050) | -5.27 (n=2,958) |

S/A/B beats D/F in all five buckets. The separation is not a favorite-longshot
artifact. It is widest at 80c and up, where a well-graded wallet paying 87c is
right more often than a poorly graded one paying the same 87c by more than six
points. The ungraded cohort is not in this table; it is a separate row in the
result above.

By category, S/A/B trades where the sample reaches 300:

| Category | Trades | Edge |
|---|---:|---:|
| Politics | 593 | +6.94 |
| Esports | 2,185 | +2.85 |
| Soccer | 15,527 | +1.77 |
| Tennis | 2,692 | +0.44 |
| Baseball | 2,557 | -1.10 |

Soccer is 63% of the S/A/B sample, so the headline number is mostly a soccer
number. Baseball runs the other way.

## What this does not show

The edge is measured at the trade's own price against settlement. It ignores
fees and slippage, and it treats every position as held to resolution. A wallet
that bought at 60c and sold at 75c before the market settled is scored on the
settlement, not on what it actually made.

Grades are computed from a wallet's own past resolved trades. The lookup is
point-in-time, so no trade is scored by a grade that saw its own outcome, but
this is not a held-out universe in the strict sense.

The scored population thinned after July, from about 18,500 wallets a day in
June and July to about 3,900 in August and September. The August and September
slices are smaller and noisier than the June and July ones.

Only settled markets are in the sample. Markets that were open on 2026-09-11 are
excluded, which tilts the sample toward shorter-dated events, and sport is most
of that.

1.57 points is a real edge and a small one. It is the size you should expect
from a market that mostly works. Nobody should read this as a reason to copy a
trade without knowing why it was made.

## The sample is not fixed

Every trade in it sits on a market that has settled, so the universe grows each
time an open market resolves. Three runs of the unchanged query on 2026-09-12,
about ninety minutes apart, returned 67,516, then 67,517, then 67,531 trades.

Bounding on `resolved_at` does not freeze it. The same nominal 02:00 UTC cutoff
returned 67,525 rather than 67,516, because rows gain an outcome after the fact
carrying a timestamp that predates the bound, and `market_outcomes` has no
ingestion clock to bound instead.

The conclusions held while the counts moved. S/A/B came out at +1.57 in all
three runs, D/F at -2.05, -2.05 and -2.06, and S/A/B beat D/F in all five price
buckets every time. A reproduction landing within a few hundredths of a point on
a slightly larger sample is the study reproducing.

Every figure above is the 02:25:45Z run, which is also what `results.md` and
`market_edge.csv` hold.

## Reproduce it

`queries.sql` holds the exact SQL, including the temp views. It reads
`whale_alerts`, `market_outcomes` and `trader_rankings` and writes nothing.
`bootstrap.py` reads the market-level export and produces the intervals.
`results.md` holds the raw output of every query in this writeup.
