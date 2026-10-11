-- 0xinsider #23678 (epic #23652, slice R2) -- section charts for /research/when-large-sports-bets-land.
--
-- Read-only against the production READ REPLICA through ./scripts/prod-read.sh (every
-- statement runs inside BEGIN READ ONLY ... ROLLBACK with a 60 s statement
-- timeout) on 2026-10-11. No row was written. Each query below is the file the run read, followed by its
-- output verbatim (psql's BEGIN/SET/ROLLBACK tags removed). The run-time reads bracket the run.
--
-- Queries 1 and 2 re-read the timing study's own universe (timing-2026-10-10.sql, view sports_buys:
-- Polymarket buys in whale_alerts on the sports categories from 2026-04-02 to 2026-09-11, settled 0 or 1
-- after the trade, 2c to 98c, kickoff on record). The study ran on a child branch forked at 11:19:48 UTC on
-- 2026-10-10; markets settled since add a few hundred buys here (401,482 there). The one-statement
-- version of query 1 timed out at 60 s on the replica, so it runs one calendar month per statement.
--
-- Query 3 is what the large-trade feed carried on sports games in the 30 days to 00:00 UTC on 2026-10-11,
-- unscored: every Polymarket buy on the same categories whose market carries a kickoff time.
--
-- The queries only, extracted from timing-charts-2026-10-11-output.txt, which holds each one followed by its output.

-- ===== run time =====
select now() as run_at_utc;

-- ===== 1-month-2026-04 =====
-- 1.04 The timing study's universe (timing-2026-10-10.sql, view sports_buys), trades from 2026-04-02 to before 2026-05-01 (UTC),
-- by stake: under $10,000 or $10,000 and up. One month per statement to stay inside the replica's 60 s timeout.
select to_char(w.traded_at at time zone 'UTC', 'YYYY-MM') trade_month,
       count(*) buys,
       count(*) filter (where w.usdc_notional_num < 10000) under_10k,
       count(*) filter (where w.usdc_notional_num >= 10000) at_least_10k,
       round(min(w.usdc_notional_num)) min_stake_usd,
       count(*) filter (where m.game_start_time <= w.traded_at) in_play
from whale_alerts w
join market_outcomes mo on mo.condition_id = w.condition_id
join markets m on m.condition_id = w.condition_id
where w.platform = 'polymarket' and w.side = 0
  and w.traded_at >= date '2026-04-02' and w.traded_at < date '2026-05-01'
  and w.category in ('Soccer','NBA','Esports','Tennis','Baseball','Hockey','Basketball','Cricket',
                     'MMA','NFL','Golf','WNBA','Formula 1','Boxing','NCAAF','NCAAB','Table Tennis',
                     'NBA Summer League','CFL','Sports','Big Game','Pickleball')
  and mo.winning_outcome in (0, 1) and mo.resolved_at > w.traded_at
  and w.price_num between 0.02 and 0.98
  and m.game_start_time is not null
group by 1 order by 1;

-- ===== 1-month-2026-05 =====
-- 1.05 The timing study's universe (timing-2026-10-10.sql, view sports_buys), trades from 2026-05-01 to before 2026-06-01 (UTC),
-- by stake: under $10,000 or $10,000 and up. One month per statement to stay inside the replica's 60 s timeout.
select to_char(w.traded_at at time zone 'UTC', 'YYYY-MM') trade_month,
       count(*) buys,
       count(*) filter (where w.usdc_notional_num < 10000) under_10k,
       count(*) filter (where w.usdc_notional_num >= 10000) at_least_10k,
       round(min(w.usdc_notional_num)) min_stake_usd,
       count(*) filter (where m.game_start_time <= w.traded_at) in_play
from whale_alerts w
join market_outcomes mo on mo.condition_id = w.condition_id
join markets m on m.condition_id = w.condition_id
where w.platform = 'polymarket' and w.side = 0
  and w.traded_at >= date '2026-05-01' and w.traded_at < date '2026-06-01'
  and w.category in ('Soccer','NBA','Esports','Tennis','Baseball','Hockey','Basketball','Cricket',
                     'MMA','NFL','Golf','WNBA','Formula 1','Boxing','NCAAF','NCAAB','Table Tennis',
                     'NBA Summer League','CFL','Sports','Big Game','Pickleball')
  and mo.winning_outcome in (0, 1) and mo.resolved_at > w.traded_at
  and w.price_num between 0.02 and 0.98
  and m.game_start_time is not null
group by 1 order by 1;

-- ===== 1-month-2026-06 =====
-- 1.06 The timing study's universe (timing-2026-10-10.sql, view sports_buys), trades from 2026-06-01 to before 2026-07-01 (UTC),
-- by stake: under $10,000 or $10,000 and up. One month per statement to stay inside the replica's 60 s timeout.
select to_char(w.traded_at at time zone 'UTC', 'YYYY-MM') trade_month,
       count(*) buys,
       count(*) filter (where w.usdc_notional_num < 10000) under_10k,
       count(*) filter (where w.usdc_notional_num >= 10000) at_least_10k,
       round(min(w.usdc_notional_num)) min_stake_usd,
       count(*) filter (where m.game_start_time <= w.traded_at) in_play
from whale_alerts w
join market_outcomes mo on mo.condition_id = w.condition_id
join markets m on m.condition_id = w.condition_id
where w.platform = 'polymarket' and w.side = 0
  and w.traded_at >= date '2026-06-01' and w.traded_at < date '2026-07-01'
  and w.category in ('Soccer','NBA','Esports','Tennis','Baseball','Hockey','Basketball','Cricket',
                     'MMA','NFL','Golf','WNBA','Formula 1','Boxing','NCAAF','NCAAB','Table Tennis',
                     'NBA Summer League','CFL','Sports','Big Game','Pickleball')
  and mo.winning_outcome in (0, 1) and mo.resolved_at > w.traded_at
  and w.price_num between 0.02 and 0.98
  and m.game_start_time is not null
group by 1 order by 1;

-- ===== 1-month-2026-07 =====
-- 1.07 The timing study's universe (timing-2026-10-10.sql, view sports_buys), trades from 2026-07-01 to before 2026-08-01 (UTC),
-- by stake: under $10,000 or $10,000 and up. One month per statement to stay inside the replica's 60 s timeout.
select to_char(w.traded_at at time zone 'UTC', 'YYYY-MM') trade_month,
       count(*) buys,
       count(*) filter (where w.usdc_notional_num < 10000) under_10k,
       count(*) filter (where w.usdc_notional_num >= 10000) at_least_10k,
       round(min(w.usdc_notional_num)) min_stake_usd,
       count(*) filter (where m.game_start_time <= w.traded_at) in_play
from whale_alerts w
join market_outcomes mo on mo.condition_id = w.condition_id
join markets m on m.condition_id = w.condition_id
where w.platform = 'polymarket' and w.side = 0
  and w.traded_at >= date '2026-07-01' and w.traded_at < date '2026-08-01'
  and w.category in ('Soccer','NBA','Esports','Tennis','Baseball','Hockey','Basketball','Cricket',
                     'MMA','NFL','Golf','WNBA','Formula 1','Boxing','NCAAF','NCAAB','Table Tennis',
                     'NBA Summer League','CFL','Sports','Big Game','Pickleball')
  and mo.winning_outcome in (0, 1) and mo.resolved_at > w.traded_at
  and w.price_num between 0.02 and 0.98
  and m.game_start_time is not null
group by 1 order by 1;

-- ===== 1-month-2026-08 =====
-- 1.08 The timing study's universe (timing-2026-10-10.sql, view sports_buys), trades from 2026-08-01 to before 2026-09-01 (UTC),
-- by stake: under $10,000 or $10,000 and up. One month per statement to stay inside the replica's 60 s timeout.
select to_char(w.traded_at at time zone 'UTC', 'YYYY-MM') trade_month,
       count(*) buys,
       count(*) filter (where w.usdc_notional_num < 10000) under_10k,
       count(*) filter (where w.usdc_notional_num >= 10000) at_least_10k,
       round(min(w.usdc_notional_num)) min_stake_usd,
       count(*) filter (where m.game_start_time <= w.traded_at) in_play
from whale_alerts w
join market_outcomes mo on mo.condition_id = w.condition_id
join markets m on m.condition_id = w.condition_id
where w.platform = 'polymarket' and w.side = 0
  and w.traded_at >= date '2026-08-01' and w.traded_at < date '2026-09-01'
  and w.category in ('Soccer','NBA','Esports','Tennis','Baseball','Hockey','Basketball','Cricket',
                     'MMA','NFL','Golf','WNBA','Formula 1','Boxing','NCAAF','NCAAB','Table Tennis',
                     'NBA Summer League','CFL','Sports','Big Game','Pickleball')
  and mo.winning_outcome in (0, 1) and mo.resolved_at > w.traded_at
  and w.price_num between 0.02 and 0.98
  and m.game_start_time is not null
group by 1 order by 1;

-- ===== 1-month-2026-09 =====
-- 1.09 The timing study's universe (timing-2026-10-10.sql, view sports_buys), trades from 2026-09-01 to before 2026-09-12 (UTC),
-- by stake: under $10,000 or $10,000 and up. One month per statement to stay inside the replica's 60 s timeout.
select to_char(w.traded_at at time zone 'UTC', 'YYYY-MM') trade_month,
       count(*) buys,
       count(*) filter (where w.usdc_notional_num < 10000) under_10k,
       count(*) filter (where w.usdc_notional_num >= 10000) at_least_10k,
       round(min(w.usdc_notional_num)) min_stake_usd,
       count(*) filter (where m.game_start_time <= w.traded_at) in_play
from whale_alerts w
join market_outcomes mo on mo.condition_id = w.condition_id
join markets m on m.condition_id = w.condition_id
where w.platform = 'polymarket' and w.side = 0
  and w.traded_at >= date '2026-09-01' and w.traded_at < date '2026-09-12'
  and w.category in ('Soccer','NBA','Esports','Tennis','Baseball','Hockey','Basketball','Cricket',
                     'MMA','NFL','Golf','WNBA','Formula 1','Boxing','NCAAF','NCAAB','Table Tennis',
                     'NBA Summer League','CFL','Sports','Big Game','Pickleball')
  and mo.winning_outcome in (0, 1) and mo.resolved_at > w.traded_at
  and w.price_num between 0.02 and 0.98
  and m.game_start_time is not null
group by 1 order by 1;

-- ===== 2-last-buy-under-10k =====
-- 2. When the last buy under $10,000 landed: the same universe, July 2026.
select max(w.traded_at) filter (where w.usdc_notional_num < 10000) last_under_10k, min(w.traded_at) filter (where w.usdc_notional_num < 10000) first_under_10k_in_july,
       count(*) buys
from whale_alerts w
join market_outcomes mo on mo.condition_id = w.condition_id
join markets m on m.condition_id = w.condition_id
where w.platform = 'polymarket' and w.side = 0
  and w.traded_at >= date '2026-07-01' and w.traded_at < date '2026-08-01'
  and w.category in ('Soccer','NBA','Esports','Tennis','Baseball','Hockey','Basketball','Cricket',
                     'MMA','NFL','Golf','WNBA','Formula 1','Boxing','NCAAF','NCAAB','Table Tennis',
                     'NBA Summer League','CFL','Sports','Big Game','Pickleball')
  and mo.winning_outcome in (0, 1) and mo.resolved_at > w.traded_at
  and w.price_num between 0.02 and 0.98
  and m.game_start_time is not null;

-- ===== 3-feed-last-30-days =====
-- 3. What the large-trade feed carried on sports games in the 30 days to the run: every Polymarket buy in
-- whale_alerts on the timing study's sports categories with a kickoff time on its market, by category and by
-- whether it landed before kickoff or in play (traded at or after the scheduled start). No settlement filter:
-- this is what a reader saw on the feed, not a scored sample.
select w.category,
       count(*) buys,
       count(*) filter (where m.game_start_time > w.traded_at) before_kickoff,
       count(*) filter (where m.game_start_time <= w.traded_at) in_play,
       round(100.0*count(*) filter (where m.game_start_time <= w.traded_at)/count(*),1) in_play_pct,
       round(min(w.usdc_notional_num)) min_stake_usd,
       min(w.traded_at) first_trade, max(w.traded_at) last_trade
from whale_alerts w
join markets m on m.condition_id = w.condition_id
where w.platform = 'polymarket' and w.side = 0
  and w.traded_at >= timestamptz '2026-09-11 00:00:00+00' and w.traded_at < timestamptz '2026-10-11 00:00:00+00'
  and w.category in ('Soccer','NBA','Esports','Tennis','Baseball','Hockey','Basketball','Cricket',
                     'MMA','NFL','Golf','WNBA','Formula 1','Boxing','NCAAF','NCAAB','Table Tennis',
                     'NBA Summer League','CFL','Sports','Big Game','Pickleball')
  and m.game_start_time is not null
group by rollup(w.category) order by buys desc;
