# Market making on Polymarket sports

Measured 2026-11-03 for the site (issue 0xinsider/0xinsider#32508):

- https://0xinsider.com/research/polymarket-market-making-sports

One snapshot of every open Polymarket sports market Gamma would page, read at 19:19:58 UTC on
2026-11-03, plus the CLOB books, the funded liquidity rewards and 24 hours of taker fills on the 40
busiest moneylines priced from 10 to 90 cents. Polymarket's public APIs only, no key, except
`kill-switch.ts`, which reads the 0xinsider large-trade feed.

0xinsider sells that feed, so it is not neutral on the last section.

## Headlines

| Measure | Result | From |
|---|---|---|
| Open sports events and markets paged | 2,100 events (Gamma answered 422 at offset 2,100), 62,342 markets, 57,957 accepting orders | `universe` |
| Median moneyline spread | 2 cents on 1,430 quoted markets; 39.5% at 1 cent or less | `byType` |
| Taker markout on moneylines a cent wide at the read (width not recorded per fill) | -0.38c at 1 minute, -0.38c at 5, -0.45c at 30, on 14,394 fills in 38 markets | `markouts.byWidth` |
| Median dollars within 2 cents of the mid, busiest books | sports $53,725 (39 books), esports $16,077 (18 books) | `books` |
| Fee schedules | every one taker-only; 41,532 markets at rate 0.05 and rebate 15%; 14,249 NFL and college football markets at 0.03 | `feeSchedules`, `feeTypes` |
| Funded sports liquidity rewards | 3,955 markets, $20,135 a day, median $4, top $476 | `rewards` |
| `secondsDelay` | 1 on 45,053 markets, 0 on 828, unset on 12,076 | `secondsDelay` |
| Large trades on the same 40 markets, 24 hours | 53; S or A wallets 23 ($487,467) | kill-switch output |

A markout here is the later minute price from `/prices-history` minus the fill price for a taker buy,
the reverse for a sell, in cents a share. A fill with no price point within two minutes of a horizon
is left out of that horizon.

## Files

- `sports-universe.ts`: pages Gamma `/events?tag_slug=sports&closed=false&order=volume24hr` and
  writes one row per market (bid, ask, fee schedule, reward settings, tick, `secondsDelay`, start
  time). Its output is about 50 MB and is not committed; rerun it for a fresh snapshot.
- `mm-scan.ts`: reads that snapshot, CLOB `POST /books`, CLOB `/rewards/markets/multi`, Data API
  `/v2/trades` and CLOB `/prices-history`, and prints every table above.
- `kill-switch.ts`: reads `/api/v1/large-trades?condition_id=` for the same 40 markets and marks each
  trade at 30 minutes. Its exported `watch()` polls for trades of $10,000 or more (the feed's floor) by wallets graded
  S or A at the trade (`min_grade_at_trade`, the basis the study buckets by) and awaits the cancel function you pass
  it, so a cancel that fails ends `watch()` with that error. It places no orders.
- `2026-11-03-mm-scan-output.json`, `2026-11-03-kill-switch-output.json`: the runs the article cites.
  The kill-switch run read its key from `OXI_API_KEY`; the committed script reads
  `OXINSIDER_API_KEY`, the only change, and ran clean at 19:32 UTC.

## Reproducing

Node 23.6 or later runs TypeScript files directly (Node 26 was used).

```
node sports-universe.ts > universe.json
node mm-scan.ts universe.json > mm-scan.json
OXINSIDER_API_KEY=... node kill-switch.ts universe.json > kill-switch.json
```

The markets move, so a rerun gives a new day's numbers, not these.
