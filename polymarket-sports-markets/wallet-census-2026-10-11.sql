-- Study 4 re-run: how many Polymarket sports bettors are profitable? (0xinsider/0xinsider#23716)
-- Read-only. Read-only role against the production read replica, 2026-10-11, 14:01 to 14:12 UTC; every
-- statement ran alone inside BEGIN READ ONLY ... ROLLBACK with a 60 s statement timeout.
--   psql "$DATABASE_URL" -X -f wallet-census-2026-10-11.sql
-- Queries 1 to 9 are wallet-census.sql's queries 1 to 9 on the same table, trader_category_stats, as it stood
-- on 2026-10-11. Its temp view `sw` is inlined as a CTE (the wrapper takes one statement), and query 7's grade
-- lookup is a per-wallet LATERAL with the cutoff moved to 2026-10-01. Queries 7b, 7c, 10, 11 and 12 are new.
-- The table changed between the runs: from 2026-09-24/25 (0xinsider/0xinsider#17655) it admits settled
-- positions known only from Polymarket's position data, and from 2026-10-07 (0xinsider/0xinsider#22353) P&L, wins, losses and
-- n_resolved include markets a wallet bought on both sides, while avg_entry_price and calibration_edge_raw
-- read one-sided markets only. The study's grade figures read query 7c (traders.latest_grade).

-- Run start.
select now() as run_at_utc;

-- Table state: when the read model was last computed, and its sports rows and wallets (the September file's unnumbered first query).
select min(computed_at) first_computed, max(computed_at) last_computed, count(*) category_rows,
       count(distinct trader_id) wallets
from trader_category_stats
where canonical_category in ('Soccer','Basketball','Esports','Tennis','Hockey','Baseball','Football','MMA','Cricket','Golf','Boxing','Sports');

-- Query 1. Sample: every wallet with a sports row, and the 20+ settled-market population the study reads.
with sw as (select trader_id, sum(n_resolved) n, sum(wins) wins, sum(losses) losses, sum(total_pnl_category) pnl, count(*) cats, sum(n_resolved*avg_entry_price)/nullif(sum(n_resolved),0) entry, sum(n_resolved*calibration_edge_raw)/nullif(sum(n_resolved),0) edge, max(last_category_trade_at) last_trade from trader_category_stats where canonical_category in ('Soccer','Basketball','Esports','Tennis','Hockey','Baseball','Football','MMA','Cricket','Golf','Boxing','Sports') group by 1)
select count(*) wallets_any, sum(n) markets_any, round(sum(pnl)/1e6,1) net_musd_any,
       count(*) filter (where n>=20) wallets_20, sum(n) filter (where n>=20) markets_20,
       round(sum(pnl) filter (where n>=20)/1e6,1) net_musd_20
from sw;

-- Query 2. Share profitable among wallets with 20+ settled sports markets, with a normal 95% half-width.
with sw as (select trader_id, sum(n_resolved) n, sum(wins) wins, sum(losses) losses, sum(total_pnl_category) pnl, count(*) cats, sum(n_resolved*avg_entry_price)/nullif(sum(n_resolved),0) entry, sum(n_resolved*calibration_edge_raw)/nullif(sum(n_resolved),0) edge, max(last_category_trade_at) last_trade from trader_category_stats where canonical_category in ('Soccer','Basketball','Esports','Tennis','Hockey','Baseball','Football','MMA','Cricket','Golf','Boxing','Sports') group by 1), pop as (select * from sw where n>=20)
select count(*) w, count(*) filter (where pnl>0) prof, round(100.0*count(*) filter (where pnl>0)/count(*),1) pct_profitable,
       round(100*1.959964*sqrt((count(*) filter (where pnl>0))::numeric/count(*)*(1-(count(*) filter (where pnl>0))::numeric/count(*))/count(*)),2) half_width_pts,
       round((percentile_cont(0.5) within group (order by pnl))::numeric) median_pnl,
       round((percentile_cont(0.1) within group (order by pnl))::numeric) p10_pnl,
       round((percentile_cont(0.9) within group (order by pnl))::numeric) p90_pnl
from pop;

-- Query 3. P&L distribution, wallets with 20+.
with sw as (select trader_id, sum(n_resolved) n, sum(wins) wins, sum(losses) losses, sum(total_pnl_category) pnl, count(*) cats, sum(n_resolved*avg_entry_price)/nullif(sum(n_resolved),0) entry, sum(n_resolved*calibration_edge_raw)/nullif(sum(n_resolved),0) edge, max(last_category_trade_at) last_trade from trader_category_stats where canonical_category in ('Soccer','Basketball','Esports','Tennis','Hockey','Baseball','Football','MMA','Cricket','Golf','Boxing','Sports') group by 1)
select case when pnl < -10000 then 'a. lost over $10k' when pnl < -1000 then 'b. lost $1k-10k' when pnl < 0 then 'c. lost under $1k'
            when pnl = 0 then 'd. flat' when pnl <= 1000 then 'e. won under $1k' when pnl <= 10000 then 'f. won $1k-10k' else 'g. won over $10k' end bucket,
       count(*) wallets, round(100.0*count(*)/sum(count(*)) over(),1) share_pct, round(sum(pnl)/1e6,1) musd
from sw where n>=20 group by 1 order by 1;

-- Query 4. Concentration: who holds the profit, wallets with 20+ ranked by P&L.
with sw as (select trader_id, sum(n_resolved) n, sum(wins) wins, sum(losses) losses, sum(total_pnl_category) pnl, count(*) cats, sum(n_resolved*avg_entry_price)/nullif(sum(n_resolved),0) entry, sum(n_resolved*calibration_edge_raw)/nullif(sum(n_resolved),0) edge, max(last_category_trade_at) last_trade from trader_category_stats where canonical_category in ('Soccer','Basketball','Esports','Tennis','Hockey','Baseball','Football','MMA','Cricket','Golf','Boxing','Sports') group by 1), s as (select pnl, ntile(100) over (order by pnl desc) pct from sw where n>=20),
     gross as (select sum(pnl) g from sw where n>=20 and pnl>0)
select case when pct=1 then 'a. top 1%' when pct<=10 then 'b. next 9%' when pct<=50 then 'c. next 40%' when pct<=90 then 'd. next 40%' else 'e. bottom 10%' end grp,
       count(*) wallets, round(sum(pnl)/1e6,1) musd, round(100.0*sum(pnl)/(select g from gross),1) pct_of_gross_profit,
       round((percentile_cont(0.5) within group (order by pnl))::numeric) median_pnl
from s group by 1 order by 1;

-- Query 5. By sport: wallets with 20+ settled markets in that sport.
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

-- Query 6. By experience: settled sports markets per wallet, union across sports.
with sw as (select trader_id, sum(n_resolved) n, sum(wins) wins, sum(losses) losses, sum(total_pnl_category) pnl, count(*) cats, sum(n_resolved*avg_entry_price)/nullif(sum(n_resolved),0) entry, sum(n_resolved*calibration_edge_raw)/nullif(sum(n_resolved),0) edge, max(last_category_trade_at) last_trade from trader_category_stats where canonical_category in ('Soccer','Basketball','Esports','Tennis','Hockey','Baseball','Football','MMA','Cricket','Golf','Boxing','Sports') group by 1)
select case when n<20 then 'a. 5-19' when n<50 then 'b. 20-49' when n<100 then 'c. 50-99' when n<500 then 'd. 100-499' when n<2000 then 'e. 500-1,999' else 'f. 2,000+' end band,
       count(*) wallets, round(100.0*count(*) filter (where pnl>0)/count(*),1) pct_profitable,
       round((percentile_cont(0.5) within group (order by pnl))::numeric) median_pnl,
       round((percentile_cont(0.1) within group (order by pnl))::numeric) p10_pnl,
       round((percentile_cont(0.9) within group (order by pnl))::numeric) p90_pnl,
       round(avg(edge)::numeric*100,2) avg_edge_pts
from sw group by 1 order by 1;

-- Query 7. By the wallet's current 0xinsider grade: its latest daily ranking dated October 1, 2026 or later
-- (September's run used September 1). A per-wallet lookup on idx_trader_rankings_latest_covering replaces the
-- September DISTINCT ON over every ranking row since the cutoff; the rule is the same: the latest ranking on
-- or after the cutoff, '(none)' when there is none. Descriptive only: the grade is computed from the same
-- settled history, so this is not a prediction test.
with sw as (select trader_id, sum(n_resolved) n, sum(wins) wins, sum(losses) losses, sum(total_pnl_category) pnl, count(*) cats, sum(n_resolved*avg_entry_price)/nullif(sum(n_resolved),0) entry, sum(n_resolved*calibration_edge_raw)/nullif(sum(n_resolved),0) edge, max(last_category_trade_at) last_trade from trader_category_stats where canonical_category in ('Soccer','Basketball','Esports','Tennis','Hockey','Baseball','Football','MMA','Cricket','Golf','Boxing','Sports') group by 1)
select coalesce(lg.grade,'(none)') grade, count(*) wallets, round(100.0*count(*)/sum(count(*)) over(),1) share_of_wallets_pct,
       round(100.0*count(*) filter (where pnl>0)/count(*),1) pct_profitable,
       round((percentile_cont(0.5) within group (order by pnl))::numeric) median_pnl,
       round(sum(pnl)/1e6,1) net_musd
from sw
left join lateral (select r.grade from trader_rankings r where r.trader_id = sw.trader_id and r.date >= date '2026-10-01' order by r.date desc limit 1) lg on true
where n>=20 group by 1
order by case coalesce(lg.grade,'(none)') when 'S' then 1 when 'A' then 2 when 'B' then 3 when 'C' then 4 when 'D' then 5 when 'F' then 6 else 7 end;

-- Query 7b (new in October). The wallets query 7 files under '(none)': their latest ranking of any date, by month,
-- with the range of those latest dates. Wallets with 20+ settled sports markets.
with sw as (select trader_id, sum(n_resolved) n, sum(total_pnl_category) pnl from trader_category_stats where canonical_category in ('Soccer','Basketball','Esports','Tennis','Hockey','Baseball','Football','MMA','Cricket','Golf','Boxing','Sports') group by 1),
pop as (select sw.*, lr.date last_rank_date, lr.grade last_grade from sw
  left join lateral (select r.date, r.grade from trader_rankings r where r.trader_id = sw.trader_id order by r.date desc limit 1) lr on true
  where n >= 20)
select case when last_rank_date is null then 'never ranked' when last_rank_date >= date '2026-10-01' then 'ranked since Oct 1' else 'last ranked ' || to_char(date_trunc('month', last_rank_date), 'YYYY-MM') end status,
       count(*) wallets, round(100.0*count(*) filter (where pnl>0)/count(*),1) pct_profitable,
       max(last_rank_date) max_date, min(last_rank_date) min_date
from pop group by 1 order by 1;

-- Query 7c (new in October). Query 7 on the grade 0xinsider shows today: traders.latest_grade, the mirror every
-- ranking write updates (backend grading_refresh.rs). NULL = unranked. Descriptive only, as query 7.
with sw as (select trader_id, sum(n_resolved) n, sum(total_pnl_category) pnl from trader_category_stats where canonical_category in ('Soccer','Basketball','Esports','Tennis','Hockey','Baseball','Football','MMA','Cricket','Golf','Boxing','Sports') group by 1)
select coalesce(t.latest_grade,'(none)') grade, count(*) wallets, round(100.0*count(*)/sum(count(*)) over(),1) share_of_wallets_pct,
       round(100.0*count(*) filter (where pnl>0)/count(*),1) pct_profitable,
       round((percentile_cont(0.5) within group (order by pnl))::numeric) median_pnl,
       round(sum(pnl)/1e6,1) net_musd
from sw left join traders t on t.id = sw.trader_id
where n>=20 group by 1
order by case coalesce(t.latest_grade,'(none)') when 'S' then 1 when 'A' then 2 when 'B' then 3 when 'C' then 4 when 'D' then 5 when 'F' then 6 else 7 end;

-- Query 8. What separates the profitable from the rest: win rate, entry price and calibration edge, wallets with 20+.
with sw as (select trader_id, sum(n_resolved) n, sum(wins) wins, sum(losses) losses, sum(total_pnl_category) pnl, count(*) cats, sum(n_resolved*avg_entry_price)/nullif(sum(n_resolved),0) entry, sum(n_resolved*calibration_edge_raw)/nullif(sum(n_resolved),0) edge, max(last_category_trade_at) last_trade from trader_category_stats where canonical_category in ('Soccer','Basketball','Esports','Tennis','Hockey','Baseball','Football','MMA','Cricket','Golf','Boxing','Sports') group by 1)
select case when pnl>0 then 'profitable' else 'not profitable' end grp, count(*) wallets,
       round((sum(wins)::numeric/nullif(sum(wins+losses),0))*100,1) win_pct,
       round(avg(entry)::numeric*100,1) avg_entry_c,
       round(avg(edge)::numeric*100,2) avg_edge_pts,
       round((percentile_cont(0.5) within group (order by edge))::numeric*100,2) median_edge_pts,
       round(100.0*count(*) filter (where edge>0)/count(*),1) pct_with_positive_edge
from sw where n>=20 group by 1 order by 1 desc;

-- Query 9. Cross-check: calibration edge sign against profitability, wallets with 20+.
with sw as (select trader_id, sum(n_resolved) n, sum(wins) wins, sum(losses) losses, sum(total_pnl_category) pnl, count(*) cats, sum(n_resolved*avg_entry_price)/nullif(sum(n_resolved),0) entry, sum(n_resolved*calibration_edge_raw)/nullif(sum(n_resolved),0) edge, max(last_category_trade_at) last_trade from trader_category_stats where canonical_category in ('Soccer','Basketball','Esports','Tennis','Hockey','Baseball','Football','MMA','Cricket','Golf','Boxing','Sports') group by 1)
select case when edge>0 then 'edge > 0' else 'edge <= 0' end edge_sign, count(*) wallets,
       round(100.0*count(*) filter (where pnl>0)/count(*),1) pct_profitable,
       round((percentile_cont(0.5) within group (order by pnl))::numeric) median_pnl
from sw where n>=20 group by 1 order by 1;

-- Query 10 (new in October; R2's query 5 of 2026-10-11-how-many-polymarket-sports-bettors-are-profitable-charts.sql.txt).
-- Survivorship: wallets by settled sports markets and by whether the wallet traded a sports market in the
-- 60 days before the run (the latest last_category_trade_at across its sports rows).
with sw as (select trader_id, sum(n_resolved) n, sum(wins) wins, sum(losses) losses, sum(total_pnl_category) pnl, count(*) cats, sum(n_resolved*avg_entry_price)/nullif(sum(n_resolved),0) entry, sum(n_resolved*calibration_edge_raw)/nullif(sum(n_resolved),0) edge, max(last_category_trade_at) last_trade from trader_category_stats where canonical_category in ('Soccer','Basketball','Esports','Tennis','Hockey','Baseball','Football','MMA','Cricket','Golf','Boxing','Sports') group by 1)
select case when n < 20 then 'a. 5-19' else 'b. 20+' end band,
       case when last_trade >= now() - interval '60 days' then 'active' else 'stopped' end status,
       count(*) wallets,
       count(*) filter (where pnl > 0) profitable,
       round(100.0*count(*) filter (where pnl > 0)/count(*),1) pct_profitable,
       round(100*1.959964*sqrt((count(*) filter (where pnl>0))::numeric/count(*)*(1-(count(*) filter (where pnl>0))::numeric/count(*))/count(*)),2) half_width_pts,
       round((percentile_cont(0.5) within group (order by pnl))::numeric) median_pnl,
       count(*) filter (where last_trade is null) no_last_trade
from sw group by 1, 2 order by 1, 2;

-- Query 11 (new in October). Coverage of the calibration fields since 0xinsider/0xinsider#22353: P&L, wins, losses and n_resolved
-- count every settled market, while avg_entry_price and calibration_edge_raw cover one-sided markets only
-- (calibration_count of them). Sports rows of wallets with 20+ settled sports markets.
with sw as (select trader_id, sum(n_resolved) n, sum(wins) wins, sum(losses) losses, sum(total_pnl_category) pnl, count(*) cats, sum(n_resolved*avg_entry_price)/nullif(sum(n_resolved),0) entry, sum(n_resolved*calibration_edge_raw)/nullif(sum(n_resolved),0) edge, max(last_category_trade_at) last_trade from trader_category_stats where canonical_category in ('Soccer','Basketball','Esports','Tennis','Hockey','Baseball','Football','MMA','Cricket','Golf','Boxing','Sports') group by 1), pop as (select trader_id from sw where n>=20)
select count(*) rows_20, sum(t.n_resolved) settled_markets, sum(t.calibration_count) one_sided_markets,
       round(100.0*sum(t.calibration_count)/sum(t.n_resolved),1) pct_one_sided,
       count(*) filter (where t.avg_entry_price is null) rows_null_entry,
       count(*) filter (where t.calibration_edge_raw is null) rows_null_edge
from trader_category_stats t join pop using (trader_id)
where t.canonical_category in ('Soccer','Basketball','Esports','Tennis','Hockey','Baseball','Football','MMA','Cricket','Golf','Boxing','Sports');

-- Query 12 (new in October). Wallets with 20+ settled sports markets whose weighted edge is NULL (no sports row
-- carries a calibration edge, so queries 8 and 9 file them under "edge <= 0"), and wallets whose edge is computed
-- over only part of their rows.
with sw as (select trader_id, sum(n_resolved) n, sum(total_pnl_category) pnl,
                   sum(n_resolved*calibration_edge_raw)/nullif(sum(n_resolved),0) edge,
                   count(*) filter (where calibration_edge_raw is null) null_rows, count(*) cats
            from trader_category_stats
            where canonical_category in ('Soccer','Basketball','Esports','Tennis','Hockey','Baseball','Football','MMA','Cricket','Golf','Boxing','Sports')
            group by 1)
select count(*) filter (where edge is null) wallets_null_edge,
       count(*) filter (where edge is null and pnl > 0) null_edge_profitable,
       count(*) filter (where null_rows > 0 and edge is not null) wallets_partial_edge
from sw where n >= 20;

-- Run end.
select now() as run_at_utc;

