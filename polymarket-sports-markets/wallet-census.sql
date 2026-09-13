-- Study 4: how many Polymarket sports bettors are profitable?
-- Read-only. Read-only role against production.  psql "$DATABASE_URL" -X -f wallet-census.sql
-- Source: trader_category_stats, the per-wallet, per-category read model. One row per (wallet, canonical
-- category) with at least 5 settled Polymarket markets in that category where the wallet had $20 or more at
-- stake and a valid entry price on the side it held. total_pnl_category = realized P&L summed over those
-- markets; n_resolved = their count; wins/losses divide the decided (nonzero P&L) markets;
-- calibration_edge_raw = mean(outcome - entry price). Owner: backend refresh_trader_category_stats.sql.
-- Sports = the canonical categories Soccer, Basketball, Esports, Tennis, Hockey, Baseball, Football, MMA,
-- Cricket, Golf, Boxing, Sports. A wallet's sports record is the union of its rows across those categories.
select now() as run_at;

select min(computed_at) first_computed, max(computed_at) last_computed, count(*) category_rows,
       count(distinct trader_id) wallets
from trader_category_stats
where canonical_category in ('Soccer','Basketball','Esports','Tennis','Hockey','Baseball','Football','MMA','Cricket','Golf','Boxing','Sports');

create temp view sw as
select trader_id, sum(n_resolved) n, sum(wins) wins, sum(losses) losses, sum(total_pnl_category) pnl, count(*) cats,
       sum(n_resolved*avg_entry_price)/sum(n_resolved) entry,
       sum(n_resolved*calibration_edge_raw)/sum(n_resolved) edge
from trader_category_stats
where canonical_category in ('Soccer','Basketball','Esports','Tennis','Hockey','Baseball','Football','MMA','Cricket','Golf','Boxing','Sports')
group by 1;

-- 1. Sample: every wallet with a sports row, and the 20+ settled-market population the study reads.
select count(*) wallets_any, sum(n) markets_any, round(sum(pnl)/1e6,1) net_musd_any,
       count(*) filter (where n>=20) wallets_20, sum(n) filter (where n>=20) markets_20,
       round(sum(pnl) filter (where n>=20)/1e6,1) net_musd_20
from sw;

-- 2. Share profitable among wallets with 20+ settled sports markets, with a normal 95% half-width.
with p as (select count(*) w, count(*) filter (where pnl>0) prof from sw where n>=20)
select w, prof, round(100.0*prof/w,1) pct_profitable,
       round(100*1.959964*sqrt((prof::numeric/w)*(1-prof::numeric/w)/w),2) half_width_pts,
       (select round((percentile_cont(0.5) within group (order by pnl))::numeric) from sw where n>=20) median_pnl,
       (select round((percentile_cont(0.1) within group (order by pnl))::numeric) from sw where n>=20) p10_pnl,
       (select round((percentile_cont(0.9) within group (order by pnl))::numeric) from sw where n>=20) p90_pnl
from p;

-- 3. P&L distribution, wallets with 20+.
select case when pnl < -10000 then 'a. lost over $10k' when pnl < -1000 then 'b. lost $1k-10k' when pnl < 0 then 'c. lost under $1k'
            when pnl = 0 then 'd. flat' when pnl <= 1000 then 'e. won under $1k' when pnl <= 10000 then 'f. won $1k-10k' else 'g. won over $10k' end bucket,
       count(*) wallets, round(100.0*count(*)/sum(count(*)) over(),1) share_pct, round(sum(pnl)/1e6,1) musd
from sw where n>=20 group by 1 order by 1;

-- 4. Concentration: who holds the profit, wallets with 20+ ranked by P&L.
with s as (select pnl, ntile(100) over (order by pnl desc) pct from sw where n>=20),
     gross as (select sum(pnl) g from sw where n>=20 and pnl>0)
select case when pct=1 then 'a. top 1%' when pct<=10 then 'b. next 9%' when pct<=50 then 'c. next 40%' when pct<=90 then 'd. next 40%' else 'e. bottom 10%' end grp,
       count(*) wallets, round(sum(pnl)/1e6,1) musd, round(100.0*sum(pnl)/(select g from gross),1) pct_of_gross_profit,
       round((percentile_cont(0.5) within group (order by pnl))::numeric) median_pnl
from s group by 1 order by 1;

-- 5. By sport: wallets with 20+ settled markets in that sport.
select canonical_category sport, count(*) wallets, sum(n_resolved) markets,
       round(100.0*count(*) filter (where total_pnl_category>0)/count(*),1) pct_profitable,
       round(100*1.959964*sqrt((count(*) filter (where total_pnl_category>0))::numeric/count(*)*(1-(count(*) filter (where total_pnl_category>0))::numeric/count(*))/count(*)),2) half_width_pts,
       round((percentile_cont(0.5) within group (order by total_pnl_category))::numeric) median_pnl,
       round((percentile_cont(0.1) within group (order by total_pnl_category))::numeric) p10_pnl,
       round((percentile_cont(0.9) within group (order by total_pnl_category))::numeric) p90_pnl,
       round(100.0*count(*) filter (where total_pnl_category>1000)/count(*),1) pct_won_over_1k,
       round(100.0*count(*) filter (where total_pnl_category< -1000)/count(*),1) pct_lost_over_1k,
       round((sum(wins)::numeric/nullif(sum(wins+losses),0))*100,1) win_pct,
       round(avg(avg_entry_price)::numeric*100,1) avg_entry_c,
       round(avg(calibration_edge_raw)::numeric*100,2) avg_edge_pts,
       round(sum(total_pnl_category)/1e6,2) net_musd
from trader_category_stats
where n_resolved >= 20 and canonical_category in ('Soccer','Basketball','Esports','Tennis','Hockey','Baseball','Football','MMA','Cricket','Golf','Boxing','Sports')
group by 1 order by 2 desc;

-- 6. By experience: settled sports markets per wallet, union across sports.
select case when n<20 then 'a. 5-19' when n<50 then 'b. 20-49' when n<100 then 'c. 50-99' when n<500 then 'd. 100-499' when n<2000 then 'e. 500-1,999' else 'f. 2,000+' end band,
       count(*) wallets, round(100.0*count(*) filter (where pnl>0)/count(*),1) pct_profitable,
       round((percentile_cont(0.5) within group (order by pnl))::numeric) median_pnl,
       round((percentile_cont(0.1) within group (order by pnl))::numeric) p10_pnl,
       round((percentile_cont(0.9) within group (order by pnl))::numeric) p90_pnl,
       round(avg(edge)::numeric*100,2) avg_edge_pts
from sw group by 1 order by 1;

-- 7. By the wallet's current 0xinsider grade (latest daily ranking dated September 1, 2026 or later).
--    Descriptive only: the grade is computed from the same settled history, so this is not a prediction test.
with lg as (select distinct on (trader_id) trader_id, grade from trader_rankings where date >= date '2026-09-01' order by trader_id, date desc)
select coalesce(lg.grade,'(none)') grade, count(*) wallets, round(100.0*count(*)/sum(count(*)) over(),1) share_of_wallets_pct,
       round(100.0*count(*) filter (where pnl>0)/count(*),1) pct_profitable,
       round((percentile_cont(0.5) within group (order by pnl))::numeric) median_pnl,
       round(sum(pnl)/1e6,1) net_musd
from sw left join lg on lg.trader_id=sw.trader_id where n>=20 group by 1
order by case coalesce(lg.grade,'(none)') when 'S' then 1 when 'A' then 2 when 'B' then 3 when 'C' then 4 when 'D' then 5 when 'F' then 6 else 7 end;

-- 8. What separates the profitable half: win rate, entry price and calibration edge, wallets with 20+.
select case when pnl>0 then 'profitable' else 'not profitable' end grp, count(*) wallets,
       round((sum(wins)::numeric/nullif(sum(wins+losses),0))*100,1) win_pct,
       round(avg(entry)::numeric*100,1) avg_entry_c,
       round(avg(edge)::numeric*100,2) avg_edge_pts,
       round((percentile_cont(0.5) within group (order by edge))::numeric*100,2) median_edge_pts,
       round(100.0*count(*) filter (where edge>0)/count(*),1) pct_with_positive_edge
from sw where n>=20 group by 1 order by 1 desc;

-- 9. Cross-check: calibration edge sign against profitability, wallets with 20+.
select case when edge>0 then 'edge > 0' else 'edge <= 0' end edge_sign, count(*) wallets,
       round(100.0*count(*) filter (where pnl>0)/count(*),1) pct_profitable,
       round((percentile_cont(0.5) within group (order by pnl))::numeric) median_pnl
from sw where n>=20 group by 1 order by 1;
