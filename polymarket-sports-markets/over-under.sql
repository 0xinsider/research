-- Study 6: over/under. Do Polymarket bettors overpay for the Over, and which way do totals settle?
-- Read-only. Read-only role against production.  psql "$DATABASE_URL" -X -f over-under.sql
-- Window 2026-04-02 .. 2026-09-13 (see the calibration study for why April 2). Grades from 2026-06-01.
-- Universe: every large-trade alert for a Polymarket BUY on a sports-category market whose
-- sports_market_type is 'totals' with outcomes Over/Under (the game total), settled after the trade, 2c-98c.
-- Outcome 0 is Over and outcome 1 is Under on these markets (outcome_yes = 'Over', outcome_no = 'Under').
select now() as run_at;

create temp view tot as
select w.id, w.trader_id, w.condition_id, w.traded_at, w.price_num, w.usdc_notional_num, w.category,
       m.sports_market_type, m.line, m.game_start_time,
       case when w.outcome_index = 0 then 'Over' else 'Under' end as side,
       (w.outcome_index = mo.winning_outcome)::int as won
from whale_alerts w
join market_outcomes mo on mo.condition_id = w.condition_id
join markets m on m.condition_id = w.condition_id
where w.platform = 'polymarket' and w.side = 0
  and w.traded_at >= date '2026-04-02' and w.traded_at < date '2026-09-14'
  and w.category in ('Soccer','NBA','Esports','Tennis','Baseball','Hockey','Basketball','Cricket',
                     'MMA','NFL','Golf','WNBA','Formula 1','Boxing','NCAAF','NCAAB','Table Tennis',
                     'NBA Summer League','CFL','Sports','Big Game','Pickleball')
  and m.sports_market_type = 'totals' and m.outcome_yes = 'Over' and m.outcome_no = 'Under'
  and mo.winning_outcome is not null and mo.resolved_at > w.traded_at
  and w.price_num between 0.02 and 0.98;

-- 1. Sample.
select count(*) buys, count(distinct trader_id) wallets, count(distinct condition_id) markets,
       round(sum(usdc_notional_num)/1e6,1) notional_musd,
       round(100.0*count(*) filter (where side='Over')/count(*),1) over_share_of_buys_pct,
       round(100.0*sum(usdc_notional_num) filter (where side='Over')/sum(usdc_notional_num),1) over_share_of_dollars_pct,
       min(traded_at)::date first_trade, max(traded_at)::date last_trade
from tot;

-- 2. Over against Under.
select side, count(*) buys, round(100.0*count(*)/sum(count(*)) over(),1) share_pct, count(distinct condition_id) markets,
       round(sum(usdc_notional_num)/1e6,1) notional_musd, round(avg(usdc_notional_num)) avg_stake_usd,
       round(avg(price_num)*100,1) avg_price_c, round(avg(won)::numeric*100,1) win_pct,
       round((avg(won)::numeric - avg(price_num))*100,2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100,2) dollar_roi_pct
from tot group by 1 order by 1;

-- 3. How settled game totals resolved, one row per market (not weighted by buys), since April 2.
select coalesce(m.category,'(none)') sport, count(*) markets,
       round(100.0*count(*) filter (where mo.winning_outcome=1)/count(*),1) under_pct,
       round(100*1.959964*sqrt(0.25/count(*)),2) half_width_pts
from markets m join market_outcomes mo on mo.condition_id = m.condition_id
where m.sports_market_type = 'totals' and m.outcome_yes = 'Over' and m.outcome_no = 'Under'
  and m.game_start_time >= timestamptz '2026-04-02' and m.game_start_time < timestamptz '2026-09-14'
  and mo.winning_outcome in (0,1)
group by rollup(1) having count(*) >= 500 order by count(*) desc;

-- 3b. Are any game-total lines whole numbers (a push is possible)? Share of settled markets by line fraction.
select case when line is null then '(no line)' when line = floor(line) then 'whole number' else 'half point' end line_kind, count(*) markets
from markets m join market_outcomes mo on mo.condition_id = m.condition_id
where m.sports_market_type = 'totals' and m.outcome_yes = 'Over' and m.outcome_no = 'Under'
  and m.game_start_time >= timestamptz '2026-04-02' and m.game_start_time < timestamptz '2026-09-14' and mo.winning_outcome in (0,1)
group by 1 order by 2 desc;

-- 4. Sport x side, sports with 300+ buys on each side.
select category sport, side, count(*) buys, round(avg(price_num)*100,1) avg_price_c, round(avg(won)::numeric*100,1) win_pct,
       round((avg(won)::numeric - avg(price_num))*100,2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100,2) dollar_roi_pct
from tot group by 1,2 having count(*) >= 300 order by 1,2;

-- 5. Price band x side.
select case when price_num < 0.4 then 'a. under 40c' when price_num < 0.6 then 'b. 40-60c' when price_num < 0.8 then 'c. 60-80c' else 'd. 80c+' end band,
       side, count(*) buys, round(avg(price_num)*100,1) avg_price_c, round(avg(won)::numeric*100,1) win_pct,
       round((avg(won)::numeric - avg(price_num))*100,2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100,2) dollar_roi_pct
from tot group by 1,2 order by 1,2;

-- 6. Pre-kickoff against in-play, by side.
select case when game_start_time is null then 'unknown' when traded_at < game_start_time then 'a. pre-kickoff' else 'b. in-play' end phase,
       side, count(*) buys, round(avg(price_num)*100,1) avg_price_c, round(avg(won)::numeric*100,1) win_pct,
       round((avg(won)::numeric - avg(price_num))*100,2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100,2) dollar_roi_pct
from tot group by 1,2 order by 1,2;

-- 7. Soccer by line, both sides, lines with 300+ buys.
select line, side, count(*) buys, round(avg(price_num)*100,1) avg_price_c, round(avg(won)::numeric*100,1) win_pct,
       round((avg(won)::numeric - avg(price_num))*100,2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100,2) dollar_roi_pct
from tot where category = 'Soccer' and line is not null group by 1,2 having count(*) >= 300 order by 1,2;

-- 8. Grade cohort x side, June 1 onward (grade coverage), point-in-time grade.
with g as (
  select t.*, case when gr.grade in ('S','A','B') then 'S/A/B' when gr.grade in ('D','F') then 'D/F' else 'other' end cohort
  from tot t left join lateral (select tr.grade from trader_rankings tr where tr.trader_id = t.trader_id and tr.date <= t.traded_at::date order by tr.date desc limit 1) gr on true
  where t.traded_at >= date '2026-06-01')
select cohort, side, count(*) buys, round(100.0*count(*)/sum(count(*)) over (partition by cohort),1) share_of_cohort_pct,
       round(avg(price_num)*100,1) avg_price_c, round(avg(won)::numeric*100,1) win_pct,
       round((avg(won)::numeric - avg(price_num))*100,2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100,2) dollar_roi_pct
from g where cohort in ('S/A/B','D/F') group by 1,2 order by 1,2;

-- 9. Month x side.
select date_trunc('month', traded_at)::date mo, side, count(*) buys, round(avg(price_num)*100,1) avg_price_c,
       round((avg(won)::numeric - avg(price_num))*100,2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100,2) dollar_roi_pct
from tot group by 1,2 order by 1,2;

-- 10. The other Over/Under families (first half, team totals, corners, tennis and table tennis match totals, kill totals), 300+ buys per side.
select m.sports_market_type family, case when w.outcome_index = 0 then 'Over' else 'Under' end side, count(*) buys,
       round(avg(w.price_num)*100,1) avg_price_c, round(avg((w.outcome_index = mo.winning_outcome)::int)::numeric*100,1) win_pct,
       round((avg((w.outcome_index = mo.winning_outcome)::int)::numeric - avg(w.price_num))*100,2) edge_pts,
       round((sum(w.usdc_notional_num*((w.outcome_index = mo.winning_outcome)::int/w.price_num-1))/sum(w.usdc_notional_num))*100,2) dollar_roi_pct
from whale_alerts w
join market_outcomes mo on mo.condition_id = w.condition_id
join markets m on m.condition_id = w.condition_id
where w.platform = 'polymarket' and w.side = 0
  and w.traded_at >= date '2026-04-02' and w.traded_at < date '2026-09-14'
  and w.category in ('Soccer','NBA','Esports','Tennis','Baseball','Hockey','Basketball','Cricket',
                     'MMA','NFL','Golf','WNBA','Formula 1','Boxing','NCAAF','NCAAB','Table Tennis',
                     'NBA Summer League','CFL','Sports','Big Game','Pickleball')
  and m.sports_market_type in ('first_half_totals','second_half_totals','team_totals','soccer_team_totals','total_corners',
                               'tennis_match_totals','table_tennis_match_totals','kill_over_under_game','soccer_first_half_team_totals')
  and m.outcome_yes = 'Over' and m.outcome_no = 'Under'
  and mo.winning_outcome is not null and mo.resolved_at > w.traded_at
  and w.price_num between 0.02 and 0.98
group by 1,2 having count(*) >= 300 order by 1,2;

-- 11. Market-level export for the clustered bootstrap: side; sport x side; phase x side; soccer line x side; cohort x side (June 1 onward).
\copy (select grp, condition_id, count(*) n, sum(won::numeric - price_num) sum_edge from (select side as grp, condition_id, won, price_num from tot union all select category || ' ' || side, condition_id, won, price_num from tot where category in ('Soccer','Baseball','NBA','Hockey') union all select (case when traded_at < game_start_time then 'pre-kickoff ' else 'in-play ' end) || side, condition_id, won, price_num from tot where game_start_time is not null union all select 'Soccer ' || line::text || ' ' || side, condition_id, won, price_num from tot where category = 'Soccer' and line in (1.5, 2.5, 3.5) union all select g.cohort || ' ' || g.side, g.condition_id, g.won, g.price_num from (select t.*, case when gr.grade in ('S','A','B') then 'S/A/B' when gr.grade in ('D','F') then 'D/F' else 'other' end cohort from tot t left join lateral (select tr.grade from trader_rankings tr where tr.trader_id = t.trader_id and tr.date <= t.traded_at::date order by tr.date desc limit 1) gr on true where t.traded_at >= date '2026-06-01') g where g.cohort in ('S/A/B','D/F')) x group by 1,2) to './over-under-market-edge.csv' with (format csv, header true)
