# Polymarket arbitrage: soccer complete sets, at size and in play

Measured 2026-11-03 for the site (issue 0xinsider/0xinsider#32509):

- https://0xinsider.com/research/polymarket-arbitrage-bot

Whether one Yes share of home, draw and away on a Polymarket soccer game ever cost less than the $1 the
set pays, or sold for more: across every scheduled and live game at 19:43 UTC, after the taker fee,
walked down the book for 100 to 5,000 shares, and in play through the night's Champions League and EFL
Championship games.

The game list and the live state and score come from the 0xinsider `/api/v1/games` endpoint, which
0xinsider sells; the books come from Polymarket's CLOB and the fee schedules from Gamma.

## Headlines

| Measure | Result | From |
|---|---|---|
| Soccer games with one home, draw and away market | 760 (759 scheduled, 1 live), 2,280 legs, every leg taker fee rate 0.05 | `arb-scan` |
| Sum of the three best Yes asks | minimum $1.00, median $1.04; 0 under $1, 0 under $1 after the fee | `arb-scan` |
| Sum of the three best Yes bids | median $0.94, maximum $1.00; 0 over $1 | `arb-scan` |
| A set at size, all in with the fee (217 sets fillable to 5,000) | $1.054 at 100 shares, $1.062 at 1,000, $1.108 at 5,000 | `arb-scan` + `derive` |
| In play, buying the set: 7 Champions League games every 5 seconds, 20:04 to 21:57 UTC | 8,914 reads, 1,338 with a leg missing an ask; of the other 7,576, 29 sets under $1 at the best asks (minimum $0.97), 8 after the fee (cheapest $0.9922), 0 for 100 shares | `live-summary` |
| In play, selling the set | 2,470 reads with a leg missing a bid; best bids over $1 on 32 reads, 7 after the fee (best $1.0403); with sizes from 20:33 UTC, 2 of 9,987 reads: Blackburn v Stoke $1.3315 for 5 sets, Man United v Roma $1.1632 for 45 | `live-summary` |

## Files

- `arb-scan.ts`: pages `/api/v1/games?sport=soccer` (scheduled and live, `OXINSIDER_API_KEY`), reads both
  outcome tokens of every leg from CLOB `POST /books` and each leg's `feeSchedule` from Gamma, and prints
  set costs at the best prices and walked down the book.
- `derive.ts`: the article's figures from the scan output.
- `live-arb-poll.ts`: the Yes asks and bids of every leg of the live games you name every 5 seconds, with
  the score from the 0xinsider live games list. Needs `OXINSIDER_API_KEY`.
- `live-sale-poll.ts`: the best Yes bids and their sizes every 5 seconds, legs from Gamma, no key.
- `live-arb-poll-v1.ts`: the first revision, which read `/games/{slug}` once per game and ran the shared
  key out of its per-minute budget from about 20:30 to 20:38 UTC. The log holds lines from both revisions.
- `live-summary.ts`: the in-play figures from the two logs; `gen-in-play.jq` emits the article's.
- `2026-11-03-*`: the outputs and logs the article cites, with each watcher's error log.

None of the scripts places an order.

## Reproducing

Node 23.6 or later runs TypeScript files directly (Node 26 was used).

```
OXINSIDER_API_KEY=... node arb-scan.ts > arb-scan.json
node derive.ts arb-scan.json
OXINSIDER_API_KEY=... node live-arb-poll.ts <live event slugs> > live.jsonl
node live-sale-poll.ts <live event slugs> > sale.jsonl
node live-summary.ts live.jsonl sale.jsonl > live-summary.json
jq -rn --slurpfile s live-summary.json -f gen-in-play.jq
```

The books move, so a rerun gives a new evening's numbers, not these. To check the article's figures,
run `derive.ts` and `live-summary.ts` on the `2026-11-03-*` files instead.
