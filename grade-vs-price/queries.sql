-- Grade vs price paid, Polymarket large buys.
-- Run 2026-09-12 against production through a read-only role.
-- Reads only. Creates temp views in the session and writes nothing.
--
--   psql "$DATABASE_URL" -X -f queries.sql

-- Universe: large buys on markets that settled after the trade.
create temp view buys as
select w.id, w.trader_id, w.condition_id, w.traded_at, w.price_num,
       w.usdc_notional_num, w.category,
       (w.outcome_index = mo.winning_outcome)::int as won
from whale_alerts w
join market_outcomes mo on mo.condition_id = w.condition_id
where w.platform = 'polymarket'
  and w.side = 0                                    -- 0 = BUY (backend/src/api_v1/side.rs)
  and w.traded_at >= date '2026-06-01'
  and w.traded_at <  date '2026-09-12'
  and w.usdc_notional_num >= 10000
  and mo.winning_outcome is not null
  and mo.resolved_at > w.traded_at                  -- settled after the trade, never before
  and w.price_num between 0.02 and 0.98;

-- Point-in-time grade: the most recent ranking dated on or before the trade day.
create temp view graded as
select b.*,
       coalesce(g.grade, '(none)') as grade,
       case when g.grade in ('S','A','B') then 'S/A/B'
            when g.grade = 'C'            then 'C'
            when g.grade in ('D','F')     then 'D/F'
            else 'no grade' end as cohort
from buys b
left join lateral (
  select tr.grade
  from trader_rankings tr
  where tr.trader_id = b.trader_id
    and tr.date <= b.traded_at::date
  order by tr.date desc
  limit 1
) g on true;

-- 1. Sample size.
select count(*) trades, count(distinct trader_id) wallets,
       count(distinct condition_id) markets,
       round(sum(usdc_notional_num)/1e6, 1) notional_musd
from buys;

-- 2. By individual grade.
select grade,
       count(*) trades,
       count(distinct trader_id) wallets,
       round(sum(usdc_notional_num)/1e6, 1) notional_musd,
       round(avg(won)::numeric * 100, 1) win_pct,
       round(avg(price_num) * 100, 1) implied_pct,
       round((avg(won)::numeric - avg(price_num)) * 100, 2) edge_pts,
       round((sum(usdc_notional_num * (won / price_num - 1))
              / sum(usdc_notional_num)) * 100, 2) dollar_roi_pct
from graded
group by grade
order by case grade when 'S' then 1 when 'A' then 2 when 'B' then 3
                    when 'C' then 4 when 'D' then 5 when 'F' then 6 else 7 end;

-- 3. By cohort.
select cohort,
       count(*) trades, count(distinct trader_id) wallets,
       count(distinct condition_id) markets,
       round(sum(usdc_notional_num)/1e6, 1) notional_musd,
       round(avg(won)::numeric * 100, 1) win_pct,
       round(avg(price_num) * 100, 1) implied_pct,
       round((avg(won)::numeric - avg(price_num)) * 100, 2) edge_pts,
       round((sum(usdc_notional_num * (won / price_num - 1))
              / sum(usdc_notional_num)) * 100, 2) dollar_roi_pct
from graded
group by cohort
order by 1;

-- 4. Favorite-longshot control: does the separation survive inside a price bucket?
select case when price_num < 0.2 then 'a. under 20c'
            when price_num < 0.4 then 'b. 20-40c'
            when price_num < 0.6 then 'c. 40-60c'
            when price_num < 0.8 then 'd. 60-80c'
            else 'e. 80c+' end as bucket,
       cohort, count(*) n,
       round((avg(won)::numeric - avg(price_num)) * 100, 2) edge_pts
from graded
where cohort in ('S/A/B', 'D/F')
group by 1, 2
order by 1, 2;

-- 5. By category, S/A/B only, samples of 300 or more.
select coalesce(category, '(uncategorized)') category,
       count(*) n,
       round((avg(won)::numeric - avg(price_num)) * 100, 2) edge_pts
from graded
where cohort = 'S/A/B'
group by 1
having count(*) >= 300
order by edge_pts desc;

-- 6. Market-level export for the clustered bootstrap in bootstrap.py.
--    Run with: psql "$DATABASE_URL" -X -f queries.sql -qAt -F',' > market_edge.csv
select cohort, condition_id, count(*) n, sum(won::numeric - price_num) sum_edge
from graded
group by 1, 2;

-- 7. Coverage check behind the window choice. Grade coverage widens in June 2026.
select date_trunc('month', date)::date as month_start,
       count(distinct date) days,
       round(avg(c)) avg_wallets_scored_per_day
from (select date, count(distinct trader_id) c from trader_rankings group by 1) t
group by 1
order by 1;
