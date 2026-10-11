-- 0xinsider #23678 (epic #23652, slice R2) -- section charts for
-- /research/nba-betting-polymarket-whale-data (the withdrawn page) from the replacement study's universe.
--
-- Read-only against the production READ REPLICA through ./scripts/prod-read.sh (every
-- statement runs inside BEGIN READ ONLY ... ROLLBACK with a 60 s statement
-- timeout) on 2026-10-11. No row was written. Each query below is the file the run read, followed by its
-- output verbatim (psql's BEGIN/SET/ROLLBACK tags removed). The run-time reads bracket the run.
--
-- Both queries read the universe of nba-pricing-2026-10-10.sql (view nba_buys: Polymarket buys
-- in whale_alerts with category 'NBA' from 2026-04-02 to 2026-09-13, settled 0 or 1 after the trade, 2c to
-- 98c) and split it by the buy's size. Query 1's total row reproduces that study's query 1: 63,037 buys,
-- $1,509.66 million, edge -0.26 points. Query 2 adds a 95% half-width clustered by market.
--
-- The queries only, extracted from nba-pricing-size-bands-2026-10-11-output.txt, which holds each one followed by its output.

-- ===== run time =====
select now() as run_at_utc;

-- ===== 1-size-bands =====
-- 1. The NBA replacement study's universe (nba-pricing-2026-10-10.sql, view nba_buys) by the buy's
-- size: does a bigger large trade win more often than its price? Same filters, read from today's replica, so
-- markets settled since October 10 can add a few rows.
select case when w.usdc_notional_num < 5000 then 'a. under $5K'
            when w.usdc_notional_num < 10000 then 'b. $5K to $10K'
            when w.usdc_notional_num < 25000 then 'c. $10K to $25K'
            when w.usdc_notional_num < 100000 then 'd. $25K to $100K'
            else 'e. $100K and up' end size_band,
       count(*) buys, count(distinct w.condition_id) markets, count(distinct w.trader_id) wallets,
       round(sum(w.usdc_notional_num)/1e6, 2) notional_musd,
       round(avg(w.price_num)*100, 1) avg_price_c,
       round(avg((w.outcome_index = mo.winning_outcome)::int)::numeric*100, 1) win_pct,
       round((avg((w.outcome_index = mo.winning_outcome)::int)::numeric - avg(w.price_num))*100, 2) edge_pts,
       round((sum(w.usdc_notional_num*((w.outcome_index = mo.winning_outcome)::int/w.price_num-1))/sum(w.usdc_notional_num))*100, 2) dollar_roi_pct
from whale_alerts w
join market_outcomes mo on mo.condition_id = w.condition_id
where w.platform = 'polymarket' and w.side = 0
  and w.traded_at >= date '2026-04-02' and w.traded_at < date '2026-09-14'
  and w.category = 'NBA'
  and mo.winning_outcome in (0, 1) and mo.resolved_at > w.traded_at
  and w.price_num between 0.02 and 0.98
group by rollup(1) order by 1;

-- ===== 2-size-band-intervals =====
-- 2. Query 1's edge by size band with a 95% half-width clustered by market: buys on one market share one result, so
-- the variance sums each market's total residual, (sum of won - price) - n_market x edge, squared, over n^2.
with b as (
  select case when w.usdc_notional_num < 5000 then 'a. under $5K'
              when w.usdc_notional_num < 10000 then 'b. $5K to $10K'
              when w.usdc_notional_num < 25000 then 'c. $10K to $25K'
              when w.usdc_notional_num < 100000 then 'd. $25K to $100K'
              else 'e. $100K and up' end size_band,
         w.condition_id, (w.outcome_index = mo.winning_outcome)::int - w.price_num resid
  from whale_alerts w
  join market_outcomes mo on mo.condition_id = w.condition_id
  where w.platform = 'polymarket' and w.side = 0
    and w.traded_at >= date '2026-04-02' and w.traded_at < date '2026-09-14'
    and w.category = 'NBA'
    and mo.winning_outcome in (0, 1) and mo.resolved_at > w.traded_at
    and w.price_num between 0.02 and 0.98
), per_market as (
  select size_band, condition_id, count(*) n_m, sum(resid) s_m from b group by 1, 2
), band as (
  select size_band, sum(n_m) n, sum(s_m) / sum(n_m) edge from per_market group by 1
)
select band.size_band, band.n buys, round(band.edge*100, 2) edge_pts,
       round(100*1.959964*sqrt(sum((pm.s_m - pm.n_m*band.edge)^2))/band.n, 2) half_width_pts
from band join per_market pm using (size_band)
group by band.size_band, band.n, band.edge order by 1;
