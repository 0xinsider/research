-- NBA favorite-longshot pricing study (#14060). Read-only, posthog_readonly, Neon branch main.
-- SUPERSEDED FOR OUTCOME SCORING (#22294, 2026-10-10). This file keeps a market once it has any settlement row
-- (`winning_outcome IS NOT NULL`) and scores won = (outcome_index = winning_outcome), so a void (-1) or
-- unresolvable (-2) market counts as a loss. The corrected run, `winning_outcome IN (0, 1)`, is nba-pricing-2026-10-10.sql.
-- The output beside this file is the record of what was first published.
-- Window starts 2026-04-02: before that day whale_alerts.outcome_index was a defaulted 0 for a large
-- share of buys (0xinsider/0xinsider#13182).
-- CORRECTED 2026-10-07 (issue 0xinsider/0xinsider#22191). The grade lookup in this file took the latest
-- trader_rankings row dated on or before the trade day. 0xinsider updates a wallet's latest ranking row in
-- place when it recomputes the grade and sets computed_at = NOW(), so that row usually held a grade written
-- after the trade (99.4% of the S, A and B buys in the sharp-money universe). Every grade lookup below now
-- also requires tr.computed_at <= the trade time. The grade rows of the committed output beside this file
-- are the September run WITH the look-ahead, kept as the record of what was published; the corrected
-- grade splits, which also keep only yes-or-no outcomes (winning_outcome IN (0, 1)), are in 2026-10-07-sports-grade-at-trade.sql.
-- Queries that do not read a grade are unchanged.
select now() as run_at;

create temp view nba_buys as
select w.id, w.trader_id, w.condition_id, w.traded_at, w.price_num, w.usdc_notional_num,
       m.sports_market_type, m.game_start_time,
       (w.outcome_index = mo.winning_outcome)::int as won
from whale_alerts w
join market_outcomes mo on mo.condition_id = w.condition_id
left join markets m on m.condition_id = w.condition_id
where w.platform = 'polymarket'
  and w.side = 0
  and w.traded_at >= date '2026-04-02'
  and w.traded_at <  date '2026-09-14'
  and w.category = 'NBA'
  and mo.winning_outcome is not null
  and mo.resolved_at > w.traded_at
  and w.price_num between 0.02 and 0.98;

-- 1. Sample.
select count(*) trades, count(distinct trader_id) wallets, count(distinct condition_id) markets,
       round(sum(usdc_notional_num)/1e6,2) notional_musd,
       min(traded_at)::date first_trade, max(traded_at)::date last_trade,
       round(avg(price_num)*100,1) avg_price_c,
       round(avg(won)::numeric*100,1) win_pct,
       round((avg(won)::numeric - avg(price_num))*100,2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100,2) dollar_roi_pct
from nba_buys;

-- 2. Calibration by 10c price bucket.
select width_bucket(price_num, 0, 1, 10) as b,
       (width_bucket(price_num, 0, 1, 10)-1)*10 || '-' || width_bucket(price_num, 0, 1, 10)*10 || 'c' as bucket,
       count(*) n,
       count(distinct condition_id) markets,
       round(sum(usdc_notional_num)/1e6,2) notional_musd,
       round(avg(price_num)*100,2) avg_price_c,
       round(avg(won)::numeric*100,2) win_pct,
       round((avg(won)::numeric - avg(price_num))*100,2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100,2) dollar_roi_pct,
       round(sum(usdc_notional_num*(won/price_num-1))/1e6,3) dollar_pnl_musd
from nba_buys
group by 1,2 order by 1;

-- 3. Fine buckets at the tails (5c).
select width_bucket(price_num, 0, 1, 20) as b,
       (width_bucket(price_num, 0, 1, 20)-1)*5 || '-' || width_bucket(price_num, 0, 1, 20)*5 || 'c' as bucket,
       count(*) n,
       round(avg(price_num)*100,2) avg_price_c,
       round(avg(won)::numeric*100,2) win_pct,
       round((avg(won)::numeric - avg(price_num))*100,2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100,2) dollar_roi_pct
from nba_buys
group by 1,2 order by 1;

-- 4. By coarse price band (longshot <30c, mid 30-70c, favorite >=70c).
select case when price_num < 0.30 then 'a. under 30c' when price_num < 0.70 then 'b. 30-70c' else 'c. 70c+' end band,
       count(*) n,
       round(avg(price_num)*100,1) avg_price_c,
       round(avg(won)::numeric*100,1) win_pct,
       round((avg(won)::numeric - avg(price_num))*100,2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100,2) dollar_roi_pct
from nba_buys
group by 1 order by 1;

-- 5. By market type (n >= 100).
select coalesce(sports_market_type,'(unknown)') market_type, count(*) n,
       round(sum(usdc_notional_num)/1e6,2) notional_musd,
       round(avg(price_num)*100,1) avg_price_c,
       round(avg(won)::numeric*100,1) win_pct,
       round((avg(won)::numeric - avg(price_num))*100,2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100,2) dollar_roi_pct
from nba_buys
group by 1 having count(*) >= 100 order by n desc;

-- 6. Market type x price band, the three core sides.
select coalesce(sports_market_type,'(unknown)') market_type,
       case when price_num < 0.30 then 'a. under 30c' when price_num < 0.70 then 'b. 30-70c' else 'c. 70c+' end band,
       count(*) n,
       round(avg(price_num)*100,1) avg_price_c,
       round(avg(won)::numeric*100,1) win_pct,
       round((avg(won)::numeric - avg(price_num))*100,2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100,2) dollar_roi_pct
from nba_buys
where sports_market_type in ('moneyline','spreads','totals')
group by 1,2 order by 1,2;

-- 7. Monthly stability of the tails: under 20c and 80c+ edge by month.
select date_trunc('month', traded_at)::date mo,
       count(*) n,
       count(*) filter (where price_num < 0.2) n_under20,
       round((avg(won) filter (where price_num < 0.2))::numeric*100 - (avg(price_num) filter (where price_num < 0.2))*100, 2) edge_under20,
       count(*) filter (where price_num >= 0.8) n_80plus,
       round((avg(won) filter (where price_num >= 0.8))::numeric*100 - (avg(price_num) filter (where price_num >= 0.8))*100, 2) edge_80plus
from nba_buys group by 1 order by 1;

-- 8. Pre-tip vs in-play.
select case when game_start_time is null then 'unknown' when traded_at < game_start_time then 'pre-tip' else 'in-play' end phase,
       count(*) n, round(avg(price_num)*100,1) implied_pct,
       round((avg(won)::numeric - avg(price_num))*100,2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100,2) dollar_roi_pct
from nba_buys group by 1 order by 1;

-- 9. Grade cohort check, for continuity with the sharp-money series (coverage widened in June, so this is a partial-season subset).
create temp view nba_graded as
select b.*, coalesce(g.grade,'(none)') grade,
       case when g.grade in ('S','A','B') then 'S/A/B' when g.grade='C' then 'C'
            when g.grade in ('D','F') then 'D/F' else 'no grade' end cohort
from nba_buys b
left join lateral (
  select tr.grade from trader_rankings tr
  where tr.trader_id = b.trader_id and tr.date <= b.traded_at::date and tr.computed_at <= b.traded_at
  order by tr.date desc limit 1
) g on true
where b.traded_at >= date '2026-06-01';

select cohort, count(*) n, count(distinct trader_id) wallets,
       round(avg(won)::numeric*100,1) win_pct, round(avg(price_num)*100,1) implied_pct,
       round((avg(won)::numeric - avg(price_num))*100,2) edge_pts
from nba_graded group by 1 order by 1;

-- 10. Wallet/market concentration, whole window.
select count(distinct trader_id) wallets, count(distinct condition_id) markets from nba_buys;
with top as (select trader_id, sum(usdc_notional_num) usd from nba_buys group by 1 order by 2 desc limit 10)
select round(100.0*sum(usd)/(select sum(usdc_notional_num) from nba_buys),1) top10_wallet_notional_share_pct from top;

-- 11. Notional floor sanity check across the window.
select date_trunc('month', traded_at)::date mo, count(*) n, round(min(usdc_notional_num)) min_notional,
       round(percentile_cont(0.5) within group (order by usdc_notional_num)) p50
from whale_alerts where platform='polymarket' and side=0 and category='NBA' and traded_at >= date '2026-04-02' group by 1 order by 1;

-- 12. Market-level export for the clustered bootstrap: overall + price band + market type groups.
\copy (select 'all' grp, condition_id, count(*) n, sum(won::numeric - price_num) sum_edge from nba_buys group by 2 union all select case when price_num < 0.30 then 'band_under30c' when price_num < 0.70 then 'band_30_70c' else 'band_70c_plus' end, condition_id, count(*), sum(won::numeric - price_num) from nba_buys group by 1,2 union all select coalesce(sports_market_type,'unknown'), condition_id, count(*), sum(won::numeric - price_num) from nba_buys where sports_market_type in ('moneyline','spreads','totals') group by 1,2) to './nba_market_edge.csv' with (format csv, header true)
