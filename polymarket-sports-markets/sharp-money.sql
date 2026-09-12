-- Study 2: do graded wallets beat the price on Polymarket sports markets?
-- Read-only. Read-only role against production.  psql "$DATABASE_URL" -X -f 02_grades.sql
-- Window 2026-06-01 .. 2026-09-11: grade coverage widened in June 2026 (238 wallets/day in May, 18,464 in June).
select now() as run_at;

create temp view sports_buys as
select w.id, w.trader_id, w.condition_id, w.traded_at, w.price_num, w.usdc_notional_num,
       w.category, m.sports_market_type, m.game_start_time,
       (w.outcome_index = mo.winning_outcome)::int as won
from whale_alerts w
join market_outcomes mo on mo.condition_id = w.condition_id
left join markets m on m.condition_id = w.condition_id
where w.platform = 'polymarket' and w.side = 0
  and w.traded_at >= date '2026-06-01' and w.traded_at < date '2026-09-12'
  and w.category in ('Soccer','NBA','Esports','Tennis','Baseball','Hockey','Basketball','Cricket',
                     'MMA','NFL','Golf','WNBA','Formula 1','Boxing','NCAAF','NCAAB','Table Tennis',
                     'NBA Summer League','CFL','Sports','Big Game','Pickleball')
  and mo.winning_outcome is not null and mo.resolved_at > w.traded_at
  and w.price_num between 0.02 and 0.98;

create temp view graded as
select b.*, coalesce(g.grade,'(none)') grade,
       case when g.grade in ('S','A','B') then 'S/A/B' when g.grade='C' then 'C'
            when g.grade in ('D','F') then 'D/F' else 'no grade' end cohort
from sports_buys b
left join lateral (
  select tr.grade from trader_rankings tr
  where tr.trader_id = b.trader_id and tr.date <= b.traded_at::date
  order by tr.date desc limit 1
) g on true;

-- 1. Sample.
select count(*) trades, count(distinct trader_id) wallets, count(distinct condition_id) markets,
       round(sum(usdc_notional_num)/1e6,1) notional_musd, min(traded_at)::date first_trade, max(traded_at)::date last_trade
from graded;

-- 2. By cohort.
select cohort, count(*) trades, count(distinct trader_id) wallets, count(distinct condition_id) markets,
       round(sum(usdc_notional_num)/1e6,1) notional_musd,
       round(avg(won)::numeric*100,1) win_pct, round(avg(price_num)*100,1) implied_pct,
       round((avg(won)::numeric - avg(price_num))*100,2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100,2) dollar_roi_pct
from graded group by 1 order by 1;

-- 3. By letter.
select grade, count(*) trades, count(distinct trader_id) wallets,
       round(sum(usdc_notional_num)/1e6,1) notional_musd,
       round(avg(won)::numeric*100,1) win_pct, round(avg(price_num)*100,1) implied_pct,
       round((avg(won)::numeric - avg(price_num))*100,2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100,2) dollar_roi_pct
from graded group by 1
order by case grade when 'S' then 1 when 'A' then 2 when 'B' then 3 when 'C' then 4 when 'D' then 5 when 'F' then 6 else 7 end;

-- 4. Sport x cohort (S/A/B vs D/F), sports with >= 500 trades in each cohort.
select category, cohort, count(*) n, count(distinct trader_id) wallets,
       round(avg(won)::numeric*100,1) win_pct, round(avg(price_num)*100,1) implied_pct,
       round((avg(won)::numeric - avg(price_num))*100,2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100,2) dollar_roi_pct
from graded
where cohort in ('S/A/B','D/F','no grade')
group by 1,2 having count(*) >= 500 order by 1,2;

-- 5. Price-bucket control, sports only.
select case when price_num < 0.2 then 'a. under 20c' when price_num < 0.4 then 'b. 20-40c'
            when price_num < 0.6 then 'c. 40-60c' when price_num < 0.8 then 'd. 60-80c' else 'e. 80c+' end bucket,
       cohort, count(*) n, round((avg(won)::numeric - avg(price_num))*100,2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100,2) dollar_roi_pct
from graded where cohort in ('S/A/B','D/F') group by 1,2 order by 1,2;

-- 6. Market type x cohort.
select coalesce(sports_market_type,'(unknown)') market_type, cohort, count(*) n,
       round((avg(won)::numeric - avg(price_num))*100,2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100,2) dollar_roi_pct
from graded where cohort in ('S/A/B','D/F') and sports_market_type in ('moneyline','spreads','totals','child_moneyline')
group by 1,2 order by 1,2;

-- 7. Pre-kickoff vs in-play x cohort.
select case when game_start_time is null then 'unknown' when traded_at < game_start_time then 'pre-kickoff' else 'in-play' end phase,
       cohort, count(*) n, round(avg(price_num)*100,1) implied_pct,
       round((avg(won)::numeric - avg(price_num))*100,2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100,2) dollar_roi_pct
from graded where cohort in ('S/A/B','D/F','no grade') group by 1,2 order by 1,2;

-- 8. Monthly stability.
select date_trunc('month', traded_at)::date mo, cohort, count(*) n,
       round((avg(won)::numeric - avg(price_num))*100,2) edge_pts
from graded where cohort in ('S/A/B','D/F') group by 1,2 order by 1,2;

-- 9. $10k+ subset for continuity with the all-category study.
select cohort, count(*) n, round((avg(won)::numeric - avg(price_num))*100,2) edge_pts
from graded where usdc_notional_num >= 10000 group by 1 order by 1;

-- 10. Wallet concentration: how many S/A/B wallets carry the trades, and the top-10 share of notional.
with s as (select trader_id, count(*) n, sum(usdc_notional_num) usd from graded where cohort='S/A/B' group by 1)
select count(*) wallets, sum(n) trades, round(sum(usd)/1e6,1) notional_musd,
       round(100.0*(select sum(usd) from (select usd from s order by usd desc limit 10) t)/sum(usd),1) top10_notional_share_pct,
       round(100.0*(select sum(n) from (select n from s order by n desc limit 10) t)/sum(n),1) top10_trade_share_pct
from s;

-- 11. Market-level export for the clustered bootstrap.
\copy (select cohort, condition_id, count(*) n, sum(won::numeric - price_num) sum_edge from graded group by 1,2) to './02_market_cohort_edge.csv' with (format csv, header true)
