-- Study 1: favorite-longshot bias on Polymarket sports markets.
-- Window starts 2026-04-02: before that day whale_alerts.outcome_index was a defaulted 0 for a large
-- share of buys (80c+ buys tagged outcome 0 won 53-56% in Feb-Mar, outcome 1 won 84-89%; both ~88% from Apr 2).
-- Read-only. Runs against production through a read-only role.
--   psql "$DATABASE_URL" -X -f 01_calibration.sql
select now() as run_at;

create temp view sports_buys as
select w.id, w.trader_id, w.condition_id, w.traded_at, w.price_num, w.usdc_notional_num,
       w.category, m.sports_market_type, m.game_start_time,
       w.best_bid_num, w.best_ask_num, w.spread_bps_num,
       (w.outcome_index = mo.winning_outcome)::int as won
from whale_alerts w
join market_outcomes mo on mo.condition_id = w.condition_id
left join markets m on m.condition_id = w.condition_id
where w.platform = 'polymarket'
  and w.side = 0                                   -- 0 = BUY (backend/src/api_v1/side.rs)
  and w.traded_at >= date '2026-04-02'
  and w.traded_at <  date '2026-09-12'
  and w.category in ('Soccer','NBA','Esports','Tennis','Baseball','Hockey','Basketball','Cricket',
                     'MMA','NFL','Golf','WNBA','Formula 1','Boxing','NCAAF','NCAAB','Table Tennis',
                     'NBA Summer League','CFL','Sports','Big Game','Pickleball')
  and mo.winning_outcome is not null
  and mo.resolved_at > w.traded_at
  and w.price_num between 0.02 and 0.98;

-- 1. Sample.
select count(*) trades, count(distinct trader_id) wallets, count(distinct condition_id) markets,
       round(sum(usdc_notional_num)/1e6,1) notional_musd,
       min(traded_at)::date first_trade, max(traded_at)::date last_trade,
       round(avg(price_num)*100,1) avg_price_c,
       round(avg(won)::numeric*100,1) win_pct,
       round((avg(won)::numeric - avg(price_num))*100,2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100,2) dollar_roi_pct
from sports_buys;

-- 2. Calibration by 10c price bucket.
select width_bucket(price_num, 0, 1, 10) as b,
       (width_bucket(price_num, 0, 1, 10)-1)*10 || '-' || width_bucket(price_num, 0, 1, 10)*10 || 'c' as bucket,
       count(*) n,
       count(distinct condition_id) markets,
       round(sum(usdc_notional_num)/1e6,1) notional_musd,
       round(avg(price_num)*100,2) avg_price_c,
       round(avg(won)::numeric*100,2) win_pct,
       round((avg(won)::numeric - avg(price_num))*100,2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100,2) dollar_roi_pct,
       round(sum(usdc_notional_num*(won/price_num-1))/1e6,2) dollar_pnl_musd
from sports_buys
group by 1,2 order by 1;

-- 3. Fine buckets at the tails (5c) to see the shape.
select width_bucket(price_num, 0, 1, 20) as b,
       (width_bucket(price_num, 0, 1, 20)-1)*5 || '-' || width_bucket(price_num, 0, 1, 20)*5 || 'c' as bucket,
       count(*) n,
       round(avg(price_num)*100,2) avg_price_c,
       round(avg(won)::numeric*100,2) win_pct,
       round((avg(won)::numeric - avg(price_num))*100,2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100,2) dollar_roi_pct
from sports_buys
group by 1,2 order by 1;

-- 4. By sport (n >= 1000).
select category, count(*) n, count(distinct condition_id) markets,
       round(sum(usdc_notional_num)/1e6,1) notional_musd,
       round(avg(price_num)*100,1) avg_price_c,
       round(avg(won)::numeric*100,1) win_pct,
       round((avg(won)::numeric - avg(price_num))*100,2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100,2) dollar_roi_pct
from sports_buys
group by 1 having count(*) >= 1000 order by n desc;

-- 5. By sport x coarse price band (longshot <30c, mid 30-70c, favorite >=70c), n >= 1000 sports.
select category,
       case when price_num < 0.30 then 'a. under 30c' when price_num < 0.70 then 'b. 30-70c' else 'c. 70c+' end band,
       count(*) n,
       round(avg(price_num)*100,1) avg_price_c,
       round(avg(won)::numeric*100,1) win_pct,
       round((avg(won)::numeric - avg(price_num))*100,2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100,2) dollar_roi_pct
from sports_buys
where category in (select category from sports_buys group by 1 having count(*) >= 1000)
group by 1,2 order by 1,2;

-- 6. By market type.
select coalesce(sports_market_type,'(unknown)') market_type, count(*) n,
       round(sum(usdc_notional_num)/1e6,1) notional_musd,
       round(avg(price_num)*100,1) avg_price_c,
       round(avg(won)::numeric*100,1) win_pct,
       round((avg(won)::numeric - avg(price_num))*100,2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100,2) dollar_roi_pct
from sports_buys
group by 1 having count(*) >= 1000 order by n desc;

-- 7. Market type x price band.
select coalesce(sports_market_type,'(unknown)') market_type,
       case when price_num < 0.30 then 'a. under 30c' when price_num < 0.70 then 'b. 30-70c' else 'c. 70c+' end band,
       count(*) n,
       round(avg(price_num)*100,1) avg_price_c,
       round(avg(won)::numeric*100,1) win_pct,
       round((avg(won)::numeric - avg(price_num))*100,2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100,2) dollar_roi_pct
from sports_buys
where sports_market_type in ('moneyline','spreads','totals','child_moneyline')
group by 1,2 order by 1,2;

-- 8. Non-sports control, same buckets, same window (for contrast).
select width_bucket(w.price_num, 0, 1, 10) as b, count(*) n,
       round(avg(w.price_num)*100,2) avg_price_c,
       round(avg((w.outcome_index = mo.winning_outcome)::int)::numeric*100,2) win_pct,
       round((avg((w.outcome_index = mo.winning_outcome)::int)::numeric - avg(w.price_num))*100,2) edge_pts
from whale_alerts w join market_outcomes mo on mo.condition_id = w.condition_id
where w.platform='polymarket' and w.side=0 and w.traded_at >= date '2026-04-02' and w.traded_at < date '2026-09-12'
  and w.category in ('Politics','Crypto','Geopolitics','Culture','Finance','World','Business')
  and mo.winning_outcome is not null and mo.resolved_at > w.traded_at and w.price_num between 0.02 and 0.98
group by 1 order by 1;

-- 9. Monthly stability of the tails: under 20c and 80c+ edge by month.
select date_trunc('month', traded_at)::date mo,
       count(*) n,
       count(*) filter (where price_num < 0.2) n_under20,
       round((avg(won) filter (where price_num < 0.2))::numeric*100 - (avg(price_num) filter (where price_num < 0.2))*100, 2) edge_under20,
       count(*) filter (where price_num >= 0.8) n_80plus,
       round((avg(won) filter (where price_num >= 0.8))::numeric*100 - (avg(price_num) filter (where price_num >= 0.8))*100, 2) edge_80plus
from sports_buys group by 1 order by 1;

-- 10. Notional floor by month (is the $1,000 alert floor constant?).
select date_trunc('month', traded_at)::date mo, count(*) n, round(min(usdc_notional_num)) min_notional,
       round(percentile_cont(0.1) within group (order by usdc_notional_num)) p10, round(percentile_cont(0.5) within group (order by usdc_notional_num)) p50
from whale_alerts where platform='polymarket' and side=0 and traded_at >= date '2026-02-01' group by 1 order by 1;

-- 11. Market-level export for clustered bootstrap: bucket, condition_id, n, sum_edge.
\copy (select width_bucket(price_num,0,1,10) as b, condition_id, count(*) n, sum(won::numeric - price_num) sum_edge from sports_buys group by 1,2) to './01_market_bucket_edge.csv' with (format csv, header true)
