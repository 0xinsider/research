-- Study 7: draws on Polymarket soccer. How often do matches draw, and do large bettors price the draw right?
-- Read-only. Read-only role against production.  psql "$DATABASE_URL" -X -f soccer-draws.sql
-- Window: kickoffs and trades 2026-04-02 .. 2026-09-13 (see the calibration study for why April 2).
-- A Polymarket soccer match is three binary markets under one event: "Will <home> win?", "Will <away> win?"
-- and "Will <home> vs. <away> end in a draw?". Legs are sports_market_type 'moneyline' with Yes/No outcomes;
-- the draw leg is identified by its group item title "Draw (...)" or a title ending "end in a draw?".
-- Outcome 0 is Yes and outcome 1 is No on every leg. Grades from 2026-06-01, point-in-time.
select now() as run_at;

create temp view legs as
select m.condition_id, m.event_slug, split_part(m.event_slug, '-', 1) league_prefix, m.game_start_time,
       case when (m.group_item_title like 'Draw (%' or m.title like '%end in a draw%') then 'draw' else 'team' end leg,
       mo.winning_outcome
from markets m
join market_outcomes mo on mo.condition_id = m.condition_id
where m.category = 'Soccer' and m.sports_market_type = 'moneyline'
  and m.outcome_yes = 'Yes' and m.outcome_no = 'No'
  and m.game_start_time >= timestamptz '2026-04-02' and m.game_start_time < timestamptz '2026-09-14'
  and mo.winning_outcome in (0, 1);

-- 1. Settled legs, and the integrity of the three-leg events: exactly one leg of a complete event resolves Yes.
with ev as (
  select event_slug, count(*) filter (where leg = 'draw') draws, count(*) filter (where leg = 'team') teams,
         count(*) filter (where winning_outcome = 0) yes_legs
  from legs group by 1)
select (select count(*) from legs where leg = 'draw') draw_legs, (select count(*) from legs where leg = 'team') team_legs,
       count(*) events, count(*) filter (where draws = 1 and teams = 2) complete_events,
       count(*) filter (where draws = 1 and teams = 2 and yes_legs = 1) complete_with_one_yes,
       round(100.0 * count(*) filter (where draws = 1 and teams = 2 and yes_legs = 1) / nullif(count(*) filter (where draws = 1 and teams = 2), 0), 2) one_yes_pct
from ev;

-- Every settled draw leg Polymarket has listed with a kickoff, for the draw rate. The April 2 boundary
-- applies to the alert table's outcome index, not to market results, so this universe runs from the first
-- listed draw market. Identified by title alone because older legs carry no sports_market_type.
create temp view draw_legs_all as
select m.condition_id, m.event_slug, split_part(m.event_slug, '-', 1) league_prefix, m.game_start_time, mo.winning_outcome, m.title
from markets m
join market_outcomes mo on mo.condition_id = m.condition_id
where m.category = 'Soccer' and (m.group_item_title like 'Draw (%' or m.title like '%end in a draw%')
  and m.outcome_yes = 'Yes' and m.game_start_time is not null and m.game_start_time < timestamptz '2026-09-14'
  and mo.winning_outcome in (0, 1);

-- 2. How often the draw happens: every settled draw leg, and the April 2 window, with binomial half-widths.
select 'all settled draw legs' universe, count(*) draws_settled, round(100.0 * count(*) filter (where winning_outcome = 0) / count(*), 1) draw_pct,
       round(100 * 1.959964 * sqrt((count(*) filter (where winning_outcome = 0))::numeric / count(*) * (1 - (count(*) filter (where winning_outcome = 0))::numeric / count(*)) / count(*)), 2) half_width_pts,
       min(game_start_time)::date first_kickoff, max(game_start_time)::date last_kickoff
from draw_legs_all
union all
select 'April 2 window, typed legs', count(*), round(100.0 * count(*) filter (where winning_outcome = 0) / count(*), 1),
       round(100 * 1.959964 * sqrt((count(*) filter (where winning_outcome = 0))::numeric / count(*) * (1 - (count(*) filter (where winning_outcome = 0))::numeric / count(*)) / count(*)), 2),
       min(game_start_time)::date, max(game_start_time)::date
from legs where leg = 'draw';

-- 2b. Draw rate by kickoff quarter.
select date_trunc('quarter', game_start_time)::date quarter, count(*) draws_settled, round(100.0 * count(*) filter (where winning_outcome = 0) / count(*), 1) draw_pct
from draw_legs_all group by 1 order by 1;

-- 3. Draw rate by competition prefix, 300 or more settled draw legs, with the latest fixture as evidence of the competition.
select league_prefix, count(*) draws_settled, round(100.0 * count(*) filter (where winning_outcome = 0) / count(*), 1) draw_pct,
       round(100 * 1.959964 * sqrt((count(*) filter (where winning_outcome = 0))::numeric / count(*) * (1 - (count(*) filter (where winning_outcome = 0))::numeric / count(*)) / count(*)), 2) half_width_pts,
       min(game_start_time)::date first_kickoff, max(game_start_time)::date last_kickoff,
       (array_agg(title order by game_start_time desc))[1] latest_fixture
from draw_legs_all group by 1 having count(*) >= 300 order by 2 desc;

-- The large buys on those legs.
create temp view buys as
select w.id, w.trader_id, w.condition_id, w.traded_at, w.outcome_index, w.price_num, w.usdc_notional_num,
       l.leg, l.league_prefix, l.game_start_time,
       case when w.outcome_index = 0 then 'Yes' else 'No' end side,
       case when w.traded_at < l.game_start_time then 'pre-kickoff' else 'in-play' end phase,
       (w.outcome_index = l.winning_outcome)::int won
from whale_alerts w
join legs l on l.condition_id = w.condition_id
join market_outcomes mo on mo.condition_id = w.condition_id
where w.platform = 'polymarket' and w.side = 0 and w.category = 'Soccer'
  and w.traded_at >= date '2026-04-02' and w.traded_at < date '2026-09-14'
  and mo.resolved_at > w.traded_at and w.price_num between 0.02 and 0.98;

-- 4. Sample of buys.
select count(*) buys, count(distinct trader_id) wallets, count(distinct condition_id) markets, round(sum(usdc_notional_num)/1e6,1) notional_musd,
       count(*) filter (where leg = 'draw') draw_buys, count(*) filter (where phase = 'in-play') in_play_buys
from buys;

-- 5. Leg x side.
select leg, side, count(*) buys, count(distinct condition_id) markets, round(sum(usdc_notional_num)/1e6,1) notional_musd,
       round(avg(price_num)*100,1) avg_price_c, round(avg(won)::numeric*100,1) win_pct,
       round((avg(won)::numeric - avg(price_num))*100,2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100,2) dollar_roi_pct
from buys group by 1,2 order by 1,2;

-- 6. Phase x leg x side.
select phase, leg, side, count(*) buys, count(distinct condition_id) markets, round(avg(price_num)*100,1) avg_price_c, round(avg(won)::numeric*100,1) win_pct,
       round((avg(won)::numeric - avg(price_num))*100,2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100,2) dollar_roi_pct
from buys group by 1,2,3 order by 1,2,3;

-- 7. Pre-kickoff draw Yes by price band.
select case when price_num < 0.20 then 'a. under 20c' when price_num < 0.25 then 'b. 20-25c' when price_num < 0.30 then 'c. 25-30c' when price_num < 0.35 then 'd. 30-35c' else 'e. 35c+' end band,
       count(*) buys, count(distinct condition_id) markets, round(avg(price_num)*100,1) avg_price_c, round(avg(won)::numeric*100,1) win_pct,
       round((avg(won)::numeric - avg(price_num))*100,2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100,2) dollar_roi_pct
from buys where phase = 'pre-kickoff' and leg = 'draw' and side = 'Yes' group by 1 order by 1;

-- 8. Pre-kickoff draw Yes, one observation per market: the average price paid against whether the match drew.
with pm as (select condition_id, avg(price_num) p, max(won) drew from buys where phase = 'pre-kickoff' and leg = 'draw' and side = 'Yes' group by 1)
select count(*) markets, round(avg(p)*100,1) avg_price_c, round(avg(drew)::numeric*100,1) draw_pct, round((avg(drew)::numeric - avg(p))*100,2) edge_pts from pm;

-- 9. Pre-kickoff team legs: favorite (Yes at 50c+) against underdog (Yes under 50c), both sides.
select case when (side = 'Yes' and price_num >= 0.5) or (side = 'No' and price_num < 0.5) then 'a. favorite leg' else 'b. underdog leg' end leg_kind,
       side, count(*) buys, count(distinct condition_id) markets, round(avg(price_num)*100,1) avg_price_c, round(avg(won)::numeric*100,1) win_pct,
       round((avg(won)::numeric - avg(price_num))*100,2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100,2) dollar_roi_pct
from buys where phase = 'pre-kickoff' and leg = 'team' group by 1,2 order by 1,2;

-- 10. In-play draw Yes by price band (a tied match late in the game prices the draw high).
select case when price_num < 0.30 then 'a. under 30c' when price_num < 0.50 then 'b. 30-50c' when price_num < 0.70 then 'c. 50-70c' else 'd. 70c+' end band,
       count(*) buys, count(distinct condition_id) markets, round(avg(price_num)*100,1) avg_price_c, round(avg(won)::numeric*100,1) win_pct,
       round((avg(won)::numeric - avg(price_num))*100,2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100,2) dollar_roi_pct
from buys where phase = 'in-play' and leg = 'draw' and side = 'Yes' group by 1 order by 1;

-- 11. Grade cohort x leg x side, June 1 onward.
with g as (
  select b.*, case when gr.grade in ('S','A','B') then 'S/A/B' when gr.grade in ('D','F') then 'D/F' else 'other' end cohort
  from buys b left join lateral (select tr.grade from trader_rankings tr where tr.trader_id = b.trader_id and tr.date <= b.traded_at::date order by tr.date desc limit 1) gr on true
  where b.traded_at >= date '2026-06-01')
select cohort, leg, side, count(*) buys, round(avg(price_num)*100,1) avg_price_c, round(avg(won)::numeric*100,1) win_pct,
       round((avg(won)::numeric - avg(price_num))*100,2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100,2) dollar_roi_pct
from g where cohort in ('S/A/B','D/F') group by 1,2,3 order by 1,2,3;

-- 12. Month x draw side.
select date_trunc('month', traded_at)::date mo, side, count(*) buys, round(avg(price_num)*100,1) avg_price_c,
       round((avg(won)::numeric - avg(price_num))*100,2) edge_pts
from buys where leg = 'draw' group by 1,2 order by 1,2;

-- 13. Concentration: the ten draw legs with the most large Yes buys, and their share.
with t as (select condition_id, count(*) n, max(won) drew, round(avg(price_num)*100,1) avg_price_c, sum(usdc_notional_num) usd from buys where leg = 'draw' and side = 'Yes' group by 1)
select (select count(*) from t) markets, (select sum(n) from t) buys,
       (select sum(n) from (select n from t order by n desc limit 10) x) top10_buys,
       (select round(100.0*sum(n)/(select sum(n) from t),1) from (select n from t order by n desc limit 10) x) top10_share_pct,
       (select sum(drew) from (select drew, n from t order by n desc limit 10) x) top10_drew;

-- 14. Market-level export for the clustered bootstrap: leg x side, phase x leg x side, pre-kickoff draw Yes by price, cohort x leg x side (June 1 onward).
\copy (select grp, condition_id, count(*) n, sum(won::numeric - price_num) sum_edge from (select leg || ' ' || side as grp, condition_id, won, price_num from buys union all select phase || ' ' || leg || ' ' || side, condition_id, won, price_num from buys union all select 'pre-kickoff draw Yes ' || case when price_num < 0.25 then 'under 25c' when price_num < 0.30 then '25-30c' else '30c+' end, condition_id, won, price_num from buys where phase = 'pre-kickoff' and leg = 'draw' and side = 'Yes' union all select g.cohort || ' ' || g.leg || ' ' || g.side, g.condition_id, g.won, g.price_num from (select b.*, case when gr.grade in ('S','A','B') then 'S/A/B' when gr.grade in ('D','F') then 'D/F' else 'other' end cohort from buys b left join lateral (select tr.grade from trader_rankings tr where tr.trader_id = b.trader_id and tr.date <= b.traded_at::date order by tr.date desc limit 1) gr on true where b.traded_at >= date '2026-06-01') g where g.cohort in ('S/A/B','D/F')) x group by 1,2) to './soccer-draws-market-edge.csv' with (format csv, header true)
