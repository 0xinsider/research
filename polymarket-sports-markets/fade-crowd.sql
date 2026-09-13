-- Study 5: fading the crowd. When poorly graded wallets pile onto one side of a Polymarket sports market
-- before kickoff, how does that side do?
-- Read-only. Read-only role against production.  psql "$DATABASE_URL" -X -f fade-crowd.sql
-- Window 2026-06-01 .. 2026-09-12 (grade coverage widened June 2026; see the sharp money study).
-- Universe: every large-trade alert for a Polymarket BUY on a sports-category market, settled after the
-- trade, 2c-98c, on a moneyline, child moneyline, spread or total (or an untyped market), placed BEFORE the
-- market's game start time. Grade is point-in-time: the latest daily ranking dated on or before the trade day.
select now() as run_at;

create temp view sb as
select w.id, w.trader_id, w.condition_id, w.traded_at, w.outcome_index, w.price_num, w.usdc_notional_num, w.category,
       m.sports_market_type, m.game_start_time, mo.winning_outcome
from whale_alerts w
join market_outcomes mo on mo.condition_id = w.condition_id
join markets m on m.condition_id = w.condition_id
where w.platform = 'polymarket' and w.side = 0
  and w.traded_at >= date '2026-06-01' and w.traded_at < date '2026-09-13'
  and w.category in ('Soccer','NBA','Esports','Tennis','Baseball','Hockey','Basketball','Cricket',
                     'MMA','NFL','Golf','WNBA','Formula 1','Boxing','NCAAF','NCAAB','Table Tennis',
                     'NBA Summer League','CFL','Sports','Big Game','Pickleball')
  and mo.winning_outcome is not null and mo.resolved_at > w.traded_at
  and w.price_num between 0.02 and 0.98
  and (m.sports_market_type in ('moneyline','child_moneyline','spreads','totals') or m.sports_market_type is null)
  and m.game_start_time is not null and w.traded_at < m.game_start_time;

create temp view g as
select b.*, case when gr.grade in ('S','A','B') then 'sab' when gr.grade in ('D','F') then 'df' else 'other' end cohort
from sb b
left join lateral (select tr.grade from trader_rankings tr where tr.trader_id = b.trader_id and tr.date <= b.traded_at::date order by tr.date desc limit 1) gr on true;

-- 1. Sample.
select count(*) buys, count(distinct trader_id) wallets, count(distinct condition_id) markets, round(sum(usdc_notional_num)/1e6,1) notional_musd,
       count(*) filter (where cohort='df') df_buys, count(*) filter (where cohort='sab') sab_buys, count(*) filter (where cohort='other') other_buys
from g;

-- 2. Baseline: pre-kickoff edge by cohort, buy-weighted, in this universe.
select cohort, count(*) buys, round(avg(price_num)*100,1) avg_price_c, round(avg((outcome_index=winning_outcome)::int)::numeric*100,1) win_pct,
       round((avg((outcome_index=winning_outcome)::int)::numeric - avg(price_num))*100,2) edge_pts
from g group by 1 order by 1;

-- One row per market: pre-kickoff dollars and buys by cohort and side, and the average price paid on each side.
create temp view mk as
select condition_id, winning_outcome, max(sports_market_type) mtype, max(category) category, min(traded_at) first_buy,
  sum(usdc_notional_num) filter (where cohort='df' and outcome_index=0) df0, sum(usdc_notional_num) filter (where cohort='df' and outcome_index=1) df1,
  sum(usdc_notional_num) filter (where cohort='sab' and outcome_index=0) sab0, sum(usdc_notional_num) filter (where cohort='sab' and outcome_index=1) sab1,
  count(*) filter (where cohort='df') n_df, count(*) filter (where cohort='sab') n_sab,
  count(distinct trader_id) filter (where cohort='df') w_df, count(distinct trader_id) filter (where cohort='sab') w_sab,
  avg(price_num) filter (where cohort='df' and outcome_index=0) dfp0, avg(price_num) filter (where cohort='df' and outcome_index=1) dfp1,
  avg(price_num) filter (where cohort='sab' and outcome_index=0) sabp0, avg(price_num) filter (where cohort='sab' and outcome_index=1) sabp1,
  avg(price_num) filter (where outcome_index=0) p0, avg(price_num) filter (where outcome_index=1) p1
from g group by 1,2;

select count(*) markets, count(*) filter (where n_df>0) with_df_buys, count(*) filter (where n_sab>0) with_sab_buys, count(*) filter (where n_df>0 and n_sab>0) with_both from mk;

-- The D/F lean: markets with $5,000+ of D/F pre-kickoff buys across 2+ buys. Side = where the larger share of
-- D/F dollars went; side price = the average price D/F buyers paid on that side; lean = that side's share.
create temp view dfl as
select *, coalesce(df0,0)+coalesce(df1,0) dft,
       case when coalesce(df0,0) >= coalesce(df1,0) then 0 else 1 end side,
       case when coalesce(df0,0) >= coalesce(df1,0) then dfp0 else dfp1 end side_price,
       case when coalesce(df0,0) >= coalesce(df1,0) then p1 else p0 end other_side_price_observed,
       greatest(coalesce(df0,0),coalesce(df1,0))/(coalesce(df0,0)+coalesce(df1,0)) lean
from mk where coalesce(df0,0)+coalesce(df1,0) >= 5000 and n_df >= 2;

create temp view sabl as
select *, coalesce(sab0,0)+coalesce(sab1,0) sabt,
       case when coalesce(sab0,0) >= coalesce(sab1,0) then 0 else 1 end side,
       case when coalesce(sab0,0) >= coalesce(sab1,0) then sabp0 else sabp1 end side_price,
       greatest(coalesce(sab0,0),coalesce(sab1,0))/(coalesce(sab0,0)+coalesce(sab1,0)) lean
from mk where coalesce(sab0,0)+coalesce(sab1,0) >= 5000 and n_sab >= 2;

-- 3. The crowd side by how one-sided the D/F money was. Fade = a flat stake on the other side at one minus
--    the crowd side's price; follow = a flat stake on the crowd side at its price. Both held to settlement, before fees.
select case when lean >= 0.9 then 'a. 90%+ one side' when lean >= 0.7 then 'b. 70-90%' else 'c. under 70%' end lean_band,
       count(*) markets, round(avg(w_df),1) avg_df_wallets, round(sum(dft)/1e6,1) df_musd,
       round(avg(side_price)*100,1) side_price_c, round(100.0*avg((side=winning_outcome)::int),1) side_won_pct,
       round((avg((side=winning_outcome)::int) - avg(side_price))*100,2) side_edge_pts,
       round(100*avg(case when side<>winning_outcome then (1/(1-side_price)-1) else -1 end),2) fade_flat_roi_pct,
       round(100*avg(case when side=winning_outcome then (1/side_price-1) else -1 end),2) follow_flat_roi_pct
from dfl group by 1 order by 1;

-- 4. The same bands for S/A/B money.
select case when lean >= 0.9 then 'a. 90%+ one side' when lean >= 0.7 then 'b. 70-90%' else 'c. under 70%' end lean_band,
       count(*) markets, round(avg(w_sab),1) avg_sab_wallets, round(sum(sabt)/1e6,1) sab_musd,
       round(avg(side_price)*100,1) side_price_c, round(100.0*avg((side=winning_outcome)::int),1) side_won_pct,
       round((avg((side=winning_outcome)::int) - avg(side_price))*100,2) side_edge_pts,
       round(100*avg(case when side=winning_outcome then (1/side_price-1) else -1 end),2) follow_flat_roi_pct
from sabl group by 1 order by 1;

-- 5. Where both cohorts have $5,000+ before kickoff: do they agree, and who is right when they do not?
with both_ as (
 select m.*, case when coalesce(df0,0) >= coalesce(df1,0) then 0 else 1 end df_side, case when coalesce(sab0,0) >= coalesce(sab1,0) then 0 else 1 end sab_side,
        case when coalesce(df0,0) >= coalesce(df1,0) then dfp0 else dfp1 end df_price, case when coalesce(sab0,0) >= coalesce(sab1,0) then sabp0 else sabp1 end sab_price
 from mk m where coalesce(df0,0)+coalesce(df1,0) >= 5000 and coalesce(sab0,0)+coalesce(sab1,0) >= 5000)
select case when df_side=sab_side then 'agree' else 'disagree' end agreement, count(*) markets,
       round(avg(sab_price)*100,1) sab_side_price_c, round(100.0*avg((sab_side=winning_outcome)::int),1) sab_side_won_pct,
       round((avg((sab_side=winning_outcome)::int) - avg(sab_price))*100,2) sab_side_edge_pts,
       round(avg(df_price)*100,1) df_side_price_c, round(100.0*avg((df_side=winning_outcome)::int),1) df_side_won_pct,
       round((avg((df_side=winning_outcome)::int) - avg(df_price))*100,2) df_side_edge_pts
from both_ group by 1 order by 1;

-- 6. D/F 90%+: crowd on the favorite against crowd on the underdog.
select case when side_price >= 0.5 then 'crowd on the favorite' else 'crowd on the underdog' end crowd_side, count(*) markets,
       round(avg(side_price)*100,1) side_price_c, round(100.0*avg((side=winning_outcome)::int),1) side_won_pct,
       round((avg((side=winning_outcome)::int) - avg(side_price))*100,2) side_edge_pts,
       round(100*avg(case when side<>winning_outcome then (1/(1-side_price)-1) else -1 end),2) fade_flat_roi_pct
from dfl where lean >= 0.9 group by 1 order by 1;

-- 7. D/F 90%+ by sport (40+ markets).
select category sport, count(*) markets, round(avg(side_price)*100,1) side_price_c, round(100.0*avg((side=winning_outcome)::int),1) side_won_pct,
       round((avg((side=winning_outcome)::int) - avg(side_price))*100,2) side_edge_pts
from dfl where lean >= 0.9 group by 1 having count(*) >= 40 order by 2 desc;

-- 8. D/F 90%+ by market type.
select coalesce(mtype,'(untyped)') market_type, count(*) markets, round(avg(side_price)*100,1) side_price_c,
       round((avg((side=winning_outcome)::int) - avg(side_price))*100,2) side_edge_pts
from dfl where lean >= 0.9 group by 1 order by 2 desc;

-- 9. D/F 90%+ by month of the first pre-kickoff buy.
select date_trunc('month', first_buy)::date mo, count(*) markets, round(avg(side_price)*100,1) side_price_c,
       round((avg((side=winning_outcome)::int) - avg(side_price))*100,2) side_edge_pts
from dfl where lean >= 0.9 group by 1 order by 1;

-- 10. D/F 90%+: sensitivity to the dollar floor.
select thr dollar_floor, count(*) markets, round(avg(side_price)*100,1) side_price_c,
       round((avg((side=winning_outcome)::int) - avg(side_price))*100,2) side_edge_pts,
       round(100*avg(case when side<>winning_outcome then (1/(1-side_price)-1) else -1 end),2) fade_flat_roi_pct
from dfl, unnest(array[5000,10000,25000,50000,100000]) thr where lean >= 0.9 and dft >= thr group by 1 order by 1;

-- 11. D/F 90%+: how the complement price compares with the price other buyers actually paid on the other side.
select count(*) markets_with_other_side_buys, round(avg(1-side_price)*100,2) complement_c, round(avg(other_side_price_observed)*100,2) observed_other_side_c,
       round(avg(other_side_price_observed - (1-side_price))*100,2) gap_c
from dfl where lean >= 0.9 and other_side_price_observed is not null;

-- 12. Market-level export for the clustered bootstrap (one row per market, so a market bootstrap is a plain bootstrap).
\copy (select grp, condition_id, 1 as n, sum_edge from (select case when lean>=0.9 then 'df_90plus' when lean>=0.7 then 'df_70_90' else 'df_under70' end grp, condition_id, ((side=winning_outcome)::int - side_price) sum_edge from dfl union all select case when lean>=0.9 then 'sab_90plus' when lean>=0.7 then 'sab_70_90' else 'sab_under70' end, condition_id, ((side=winning_outcome)::int - side_price) from sabl union all select case when side_price >= 0.5 then 'df_90plus_favorite' else 'df_90plus_underdog' end, condition_id, ((side=winning_outcome)::int - side_price) from dfl where lean >= 0.9) x) to './fade-crowd-market-edge.csv' with (format csv, header true)
