-- #23679 (epic #23652, slice R4): section charts for /research/cashing-out-polymarket-sports.
--
-- WHERE IT RAN. On a Neon child branch of production forked at 13:03:53 UTC on 2026-10-11
-- (claude18-23679-charts, deleted after the runs), through
-- ./scripts/neon-child-branch.sh query --name claude18-23679-charts -f <this file>, read-only statements only.
-- The run_at line of the committed -output.txt beside this file is the start of the run.
--
-- WHAT IT ADDS. The study itself is cash-out-2026-10-10.sql (its universe, sign convention and
-- bootstrap). This file re-builds the same universe and adds the cuts the section charts need:
--   1. the universe re-built as of this run, to show how the counts grow as markets settle. The October 10
--      universe cannot be rebuilt row for row: market_outcomes keeps no write time (recorded_at is null on
--      every row here), and every settlement here has resolved_at before that run's fork, so the sells
--      added since sit on markets whose settlement row was written after the fork;
--   2. a market-level export by sport and by calendar month for the clustered bootstrap
--      (bootstrap-2026-09-13.py, seed 20260913), which the October 10 run did not bootstrap;
--   3. shares and cash on the ten markets with the most sells under 20c: what holding would have paid;
--   4. the size floor the large-trade table actually applied, month by month (the article said the floor
--      rose from $1,000 to $10,000 in August; the code says $2,996 to $10,000 on July 2);
--   5. what the void-market correction left out: sells on markets that settled void or unresolvable;
--   6. the large-trade feed over the 30 days to October 11, 2026: sports trades by side and sport.
-- Value given up (won minus price) is the query sign, as in the study; the article negates it (exit edge).
select now() as run_at;

-- The study's universe, every sell, whatever the settlement.
create temp table sells_all as
select w.condition_id, w.trader_id, w.traded_at, w.outcome_index, w.price_num, w.usdc_notional_num, w.shares_num, w.category,
       case when m.game_start_time is null then 'unknown' when w.traded_at < m.game_start_time then 'pre-kickoff' else 'in-play' end phase,
       mo.winning_outcome, (w.outcome_index = mo.winning_outcome)::int as won
from whale_alerts w
join market_outcomes mo on mo.condition_id = w.condition_id
left join markets m on m.condition_id = w.condition_id
where w.platform = 'polymarket' and w.side = 1
  and w.traded_at >= date '2026-04-02' and w.traded_at < date '2026-09-14'
  and w.category in ('Soccer','NBA','Esports','Tennis','Baseball','Hockey','Basketball','Cricket',
                     'MMA','NFL','Golf','WNBA','Formula 1','Boxing','NCAAF','NCAAB','Table Tennis',
                     'NBA Summer League','CFL','Sports','Big Game','Pickleball')
  and mo.resolved_at > w.traded_at
  and w.price_num between 0.02 and 0.98;

-- The study's universe as of this run: markets that settled yes or no.
create temp table sells as
select * from sells_all where winning_outcome in (0, 1);

-- 1. The study's query 1 and 2 as of this run (the October 10 run: 38,601 sells, 8,928 markets, 64.1c, 64.9%, 0.87).
select count(*) sells, count(distinct condition_id) markets, round(avg(price_num)*100,1) avg_price_c,
       round(avg(won)::numeric*100,1) sold_outcome_won_pct, round((avg(won)::numeric - avg(price_num))*100,2) value_given_up_pts
from sells;

-- 2. By sport and by month, as the October 10 run printed them (queries 6 and 10 there), to compare.
select category sport, count(*) n, round(avg(price_num)*100,1) avg_price_c, round((avg(won)::numeric - avg(price_num))*100,2) value_given_up_pts,
       count(distinct condition_id) markets
from sells group by 1 having count(*) >= 1000 order by 2 desc;
select date_trunc('month', traded_at)::date mo, count(*) n, round((avg(won)::numeric - avg(price_num))*100,2) value_given_up_pts,
       count(distinct condition_id) markets
from sells group by 1 order by 1;

-- 2b. September, the month whose sample is smallest: its sells by sport.
select category sport, count(*) n, count(distinct condition_id) markets, round(avg(price_num)*100,1) avg_price_c,
       round(avg(won)::numeric*100,1) sold_outcome_won_pct, round((avg(won)::numeric - avg(price_num))*100,2) value_given_up_pts,
       round(100.0*avg((phase = 'in-play')::int),1) in_play_pct
from sells where traded_at >= date '2026-09-01' group by 1 order by 2 desc;

-- 3. The ten markets with the most sells under 20c: cash received, shares sold, and what the shares paid.
with t as (select condition_id, count(*) n, max(won) won, round(avg(price_num)*100,1) avg_price_c, sum(usdc_notional_num) cash, sum(shares_num) shares
           from sells where price_num < 0.20 group by 1)
select t.n, t.won, t.avg_price_c, round(t.cash) cash_usd, round(t.shares) shares, round(t.shares * t.won) paid_at_settlement_usd,
       round(t.cash - t.shares * t.won) selling_minus_holding_usd, m.title
from t left join markets m on m.condition_id = t.condition_id order by t.n desc limit 10;

-- 4. The size floor the table applied: every sports alert (both sides) in the window, by month.
select date_trunc('month', w.traded_at)::date mo, count(*) alerts, round(min(w.usdc_notional_num)) min_usd,
       round((percentile_cont(0.05) within group (order by w.usdc_notional_num))::numeric) p5_usd,
       round(100.0*avg((w.usdc_notional_num < 3000)::int),1) under_3k_pct, round(100.0*avg((w.usdc_notional_num < 10000)::int),1) under_10k_pct
from whale_alerts w
where w.platform = 'polymarket' and w.traded_at >= date '2026-04-02' and w.traded_at < date '2026-09-14'
  and w.category in ('Soccer','NBA','Esports','Tennis','Baseball','Hockey','Basketball','Cricket',
                     'MMA','NFL','Golf','WNBA','Formula 1','Boxing','NCAAF','NCAAB','Table Tennis',
                     'NBA Summer League','CFL','Sports','Big Game','Pickleball')
group by 1 order by 1;
-- The sells themselves: the smallest, and the last sell under $3,000 and under $10,000.
select min(usdc_notional_num) min_usd, max(traded_at) filter (where usdc_notional_num < 3000) last_under_3k,
       max(traded_at) filter (where usdc_notional_num < 10000) last_under_10k, min(traded_at) first_sell
from sells_all;

-- 5. What the correction left out: sells on markets that settled void (-1) or could not be resolved (-2).
select winning_outcome, count(*) sells, count(distinct condition_id) markets, round(avg(price_num)*100,1) avg_price_c
from sells_all where winning_outcome not in (0, 1)
group by 1 order by 1;

-- 6. The large-trade feed over the 30 days to October 11, 2026: sports alerts by sport and side, with the in-play share.
create temp table feed as
select w.category, w.side, w.usdc_notional_num, case when m.game_start_time is null then 'unknown' when w.traded_at < m.game_start_time then 'pre' else 'in-play' end phase
from whale_alerts w left join markets m on m.condition_id = w.condition_id
where w.platform = 'polymarket' and w.traded_at >= timestamptz '2026-09-11 00:00+00' and w.traded_at < timestamptz '2026-10-11 00:00+00'
  and w.category in ('Soccer','NBA','Esports','Tennis','Baseball','Hockey','Basketball','Cricket',
                     'MMA','NFL','Golf','WNBA','Formula 1','Boxing','NCAAF','NCAAB','Table Tennis',
                     'NBA Summer League','CFL','Sports','Big Game','Pickleball');
select coalesce(category, 'all sports') sport, count(*) alerts, count(*) filter (where side = 0) buys, count(*) filter (where side = 1) sells,
       round(100.0*avg((side = 1)::int),1) sell_pct,
       round(100.0*avg((phase = 'in-play')::int) filter (where side = 0),1) buy_in_play_pct,
       round(100.0*avg((phase = 'in-play')::int) filter (where side = 1),1) sell_in_play_pct,
       round(sum(usdc_notional_num) filter (where side = 1)) sell_usd
from feed group by rollup(category) order by 2 desc limit 12;

-- 7. Market-level export by sport (sports with 1,000 or more sells) and by month, for the bootstrap.
\copy (select grp, condition_id, count(*) n, sum(won::numeric - price_num) sum_edge from (select 'sport ' || category grp, condition_id, won, price_num from sells where category in (select category from sells group by 1 having count(*) >= 1000) union all select 'month ' || to_char(traded_at, 'YYYY-MM'), condition_id, won, price_num from sells) x group by 1,2 order by 1,2) to './cash-out-charts-2026-10-11-market-edge.csv' with (format csv, header true)
