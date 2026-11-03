# Polymarket live (in-play) markets

Measured 2026-11-03 for the site (issue 0xinsider/0xinsider#32523):

- https://0xinsider.com/research/polymarket-live-in-play-markets

One evening of Polymarket sports books: a snapshot of every open sports moneyline at 20:16 UTC, one-minute
price history for the games that closed in the 24 hours before 20:10 UTC, nine soccer books read every 2
seconds across their start, and the night's 7 Champions League and 8 EFL Championship games read every
30 seconds from before kickoff to the final whistle, with Gamma's score and the 0xinsider live games list
read every 10 seconds beside them.

The live watchers take state, clock and score from the 0xinsider live games list, which 0xinsider sells,
and one section compares that list with Gamma; the frozen score feed it records is filed as
0xinsider/0xinsider#32735.

## Headlines

| Measure | Result | From |
|---|---|---|
| Resting dollars on a soccer book at the first read after the start (at most 1.1 s in) | median 12% of the last read before it, 9 books in 3 games; the 3 Guatemala books read $0 | `kickoff-summary` + `gen-kickoff.jq` |
| Same books 1 and 10 minutes in | median 18% and 63% | `kickoff-summary` |
| Champions League books within 2 cents of the mid, minutes 0 to 15 against 40 minutes before | median 14.3% ($201,388 to $34,027), 12 books | `depth-summary` |
| Soccer moneylines within 2 cents of the mid by time to start | in play $4,470 (66 books); 3 to 7 days out $192 (384 books) | `depth-by-kickoff` |
| `secondsDelay` on open moneylines | 1 on 1,383 of 1,413; 0 on 30, all NBA | `depth-by-kickoff` |
| 5-cent jumps fully undone an hour later | in play 40.6%, before the start 28.3% | `move-study` |
| Depth within 2 cents of the mid around a goal, against the book's own level 4 to 8 minutes earlier | median 17% 90 seconds before the score read, 51% at the score read; 31 goals | `depth-summary` + `gen-live-evidence.jq` |
| Gamma's score against the 0xinsider live list, read every 10 seconds | 26 goals both caught cleanly: the 0xinsider list first 25 times, Gamma never, by a median 125 seconds | `score-race-summary` |
| Score feeds after the book, 12 goals with a book time | 0xinsider list a median 104.5 seconds, Gamma 204 | `score-race-summary` |
| Scoring side's 5-cent jump to the score read, Champions League, 5-second books | median 116 seconds over 11 goals, never under 75 | `score-lag` |

## Files

- `depth-by-kickoff.ts`: pages Gamma's open sports events, reads every moneyline Yes book from CLOB
  `POST /books`, and buckets depth and spread by time to the listed start; also counts `secondsDelay` by
  league.
- `move-study.ts`: one-minute CLOB `/prices-history` for moneylines on games that closed in the last 24
  hours, and the 5-cent jumps in it, pregame and in play.
- `kickoff-clear-poll.ts`: every Yes book of the games you name, every 2 seconds, across their
  `gameStartTime`. Public data, no key. `kickoff-summary.ts` turns its log into resting dollars before
  and after the start; `gen-kickoff.jq` emits the article's figures from that.
- `depth-live-poll.ts`: every Yes book of the live games you name every 30 seconds, with state, clock and
  score from `/api/v1/games?status=live`. Needs `OXINSIDER_API_KEY`. `depth-live-poll-v1.ts` is the
  first revision, which read `/games/{slug}` once per game and ran the shared key out of its per-minute
  budget from about 20:30 to 20:38 UTC.
- `depth-summary.ts`: the goal profile and the pregame-to-early-play comparison. Its pregame side reads
  `mm-scan` output from `polymarket-market-making` in this repository.
- `score-race-poll.ts`: Gamma event `score` and the 0xinsider live list every 10 seconds, logged on each
  change. Needs `OXINSIDER_API_KEY`. `score-race-summary.ts` decides which showed each goal first.
- `score-lag.ts`: book move to score read on the Champions League games, from the 5-second log in
  `polymarket-arbitrage` (`2026-11-03-live-arb-poll-output.jsonl`).
- `gen-live-evidence.jq`: emits the goal and score figures from the three summaries.
- `2026-11-03-*`: the logs and outputs the article cites. The kickoff log keeps the reads from 90
  seconds before to 11 minutes after each listed start; its summary is the same as the full log's.

None of the scripts places an order.

## Reproducing

Node 23.6 or later runs TypeScript files directly (Node 26 was used).

```
node depth-by-kickoff.ts > depth-by-kickoff.json
node move-study.ts > move-study.json
node kickoff-clear-poll.ts <event slugs> > kickoff.jsonl
node kickoff-summary.ts kickoff.jsonl > kickoff-summary.json
OXINSIDER_API_KEY=... node depth-live-poll.ts <live event slugs> > depth-live.jsonl
node depth-summary.ts depth-live.jsonl ../polymarket-market-making/2026-11-03-mm-scan-output.json > depth-summary.json
OXINSIDER_API_KEY=... node score-race-poll.ts <live event slugs> > score-race.jsonl 2> score-race.err
node score-race-summary.ts score-race.jsonl score-race.err live-arb.jsonl depth-live.jsonl > score-race-summary.json
node score-lag.ts live-arb.jsonl > score-lag.json
jq -r -f gen-kickoff.jq kickoff-summary.json
jq -rn --slurpfile d depth-summary.json --slurpfile r score-race-summary.json --slurpfile l score-lag.json -f gen-live-evidence.jq
```

`live-arb.jsonl` is the log of `../polymarket-arbitrage/live-arb-poll.ts` over the same games; that night's is `../polymarket-arbitrage/2026-11-03-live-arb-poll-output.jsonl`. The watchers read the night you run them, so a rerun gives a new evening's numbers, not these. Run the summaries on the `2026-11-03-*` logs to get these.
