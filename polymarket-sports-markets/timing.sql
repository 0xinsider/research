-- Study 3: when large sports bets land relative to kickoff, and which timing wins.
-- Read-only. Read-only role against production.  psql "$DATABASE_URL" -X -f 03_timing.sql
-- Window 2026-04-02 .. 2026-09-11 (see study 1 for why April 2). Grades from 2026-06-01.
select now() as run_at;

create temp view sports_buys as
select w.id, w.trader_id, w.condition_id, w.traded_at, w.price_num, w.usdc_notional_num,
       w.category, m.sports_market_type, m.game_start_time,
       w.best_bid_num, w.best_ask_num,
       extract(epoch from (m.game_start_time - w.traded_at))/3600.0 as hours_to_kickoff,
       (w.outcome_index = mo.winning_outcome)::int as won
from whale_alerts w
join market_outcomes mo on mo.condition_id = w.condition_id
join markets m on m.condition_id = w.condition_id
where w.platform = 'polymarket' and w.side = 0
  and w.traded_at >= date '2026-04-02' and w.traded_at < date '2026-09-12'
  and w.category in ('Soccer','NBA','Esports','Tennis','Baseball','Hockey','Basketball','Cricket',
                     'MMA','NFL','Golf','WNBA','Formula 1','Boxing','NCAAF','NCAAB','Table Tennis',
                     'NBA Summer League','CFL','Sports','Big Game','Pickleball')
  and mo.winning_outcome is not null and mo.resolved_at > w.traded_at
  and w.price_num between 0.02 and 0.98
  and m.game_start_time is not null;

create temp view timed as
select *, case when hours_to_kickoff > 168 then 'a. 7d+ before'
               when hours_to_kickoff > 24  then 'b. 1-7d before'
               when hours_to_kickoff > 6   then 'c. 6-24h before'
               when hours_to_kickoff > 1   then 'd. 1-6h before'
               when hours_to_kickoff > 0   then 'e. last hour'
               when hours_to_kickoff > -1  then 'f. in-play, first hour'
               when hours_to_kickoff > -2  then 'g. in-play, second hour'
               else 'h. in-play, 2h+' end as bucket
from sports_buys;

-- 1. Sample.
select count(*) trades, count(distinct trader_id) wallets, count(distinct condition_id) markets,
       round(sum(usdc_notional_num)/1e6,1) notional_musd,
       count(*) filter (where hours_to_kickoff > 0) pre_kickoff, count(*) filter (where hours_to_kickoff <= 0) in_play,
       round(100.0*count(*) filter (where hours_to_kickoff <= 0)/count(*),1) in_play_pct,
       round(100.0*sum(usdc_notional_num) filter (where hours_to_kickoff <= 0)/sum(usdc_notional_num),1) in_play_notional_pct
from timed;

-- 2. Distribution and outcome by timing bucket.
select bucket, count(*) n, round(100.0*count(*)/sum(count(*)) over (),1) share_pct,
       round(sum(usdc_notional_num)/1e6,1) notional_musd,
       round(avg(usdc_notional_num)) avg_stake_usd,
       round(avg(price_num)*100,1) avg_price_c, round(avg(won)::numeric*100,1) win_pct,
       round((avg(won)::numeric - avg(price_num))*100,2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100,2) dollar_roi_pct
from timed group by 1 order by 1;

-- 3. Pre-kickoff vs in-play by sport (n >= 1000).
select category, case when hours_to_kickoff > 0 then 'pre-kickoff' else 'in-play' end phase,
       count(*) n, round(avg(price_num)*100,1) avg_price_c,
       round((avg(won)::numeric - avg(price_num))*100,2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100,2) dollar_roi_pct
from timed group by 1,2 having count(*) >= 1000 order by 1,2;

-- 4. In-play share by sport.
select category, count(*) n, round(100.0*count(*) filter (where hours_to_kickoff <= 0)/count(*),1) in_play_pct
from timed group by 1 having count(*) >= 1000 order by 3 desc;

-- 5. Price distribution by timing: share of buys at 80c+ and under 20c.
select bucket, count(*) n,
       round(100.0*count(*) filter (where price_num >= 0.8)/count(*),1) pct_80plus,
       round(100.0*count(*) filter (where price_num < 0.2)/count(*),1) pct_under20,
       round(100.0*count(*) filter (where price_num between 0.4 and 0.6)/count(*),1) pct_40_60
from timed group by 1 order by 1;

-- 6. Price-band x phase calibration (does in-play favorite buying calibrate?).
select case when hours_to_kickoff > 0 then 'pre-kickoff' else 'in-play' end phase,
       case when price_num < 0.30 then 'a. under 30c' when price_num < 0.70 then 'b. 30-70c' else 'c. 70c+' end band,
       count(*) n, round(avg(price_num)*100,1) avg_price_c, round(avg(won)::numeric*100,1) win_pct,
       round((avg(won)::numeric - avg(price_num))*100,2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100,2) dollar_roi_pct
from timed group by 1,2 order by 1,2;

-- 7. Grade cohort x timing (June 1 onward).
create temp view timed_graded as
select t.*, case when g.grade in ('S','A','B') then 'S/A/B' when g.grade='C' then 'C'
                 when g.grade in ('D','F') then 'D/F' else 'no grade' end cohort
from timed t
left join lateral (select tr.grade from trader_rankings tr where tr.trader_id = t.trader_id and tr.date <= t.traded_at::date order by tr.date desc limit 1) g on true
where t.traded_at >= date '2026-06-01';

select cohort, count(*) n,
       round(100.0*count(*) filter (where hours_to_kickoff > 24)/count(*),1) pct_day_plus_before,
       round(100.0*count(*) filter (where hours_to_kickoff > 0 and hours_to_kickoff <= 24)/count(*),1) pct_same_day_before,
       round(100.0*count(*) filter (where hours_to_kickoff <= 0)/count(*),1) pct_in_play
from timed_graded group by 1 order by 1;

select bucket, cohort, count(*) n, round((avg(won)::numeric - avg(price_num))*100,2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100,2) dollar_roi_pct
from timed_graded where cohort in ('S/A/B','D/F','no grade') group by 1,2 order by 1,2;

-- 8. Quoted spread at trade time by timing (quotes exist through July 2026), pre-kickoff and in-play, in cents.
select bucket, count(best_bid_num) n_quoted,
       round((percentile_cont(0.5) within group (order by (best_ask_num - best_bid_num)))::numeric*100, 1) median_spread_c,
       round((avg(best_ask_num - best_bid_num))::numeric*100, 1) mean_spread_c
from timed where best_bid_num is not null and best_ask_num is not null and best_ask_num >= best_bid_num and traded_at < date '2026-08-01'
group by 1 order by 1;

-- 9. Quoted spread by sport, pre-kickoff, in cents.
select category, count(best_bid_num) n_quoted,
       round((percentile_cont(0.5) within group (order by (best_ask_num - best_bid_num)))::numeric*100, 1) median_spread_c,
       round((percentile_cont(0.9) within group (order by (best_ask_num - best_bid_num)))::numeric*100, 1) p90_spread_c
from timed where best_bid_num is not null and best_ask_num is not null and best_ask_num >= best_bid_num and traded_at < date '2026-08-01' and hours_to_kickoff > 0
group by 1 having count(best_bid_num) >= 500 order by 3;

-- 10. Market-level export for clustered bootstrap by bucket.
\copy (select bucket, condition_id, count(*) n, sum(won::numeric - price_num) sum_edge from timed group by 1,2) to './03_market_bucket_edge.csv' with (format csv, header true)
