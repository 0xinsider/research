-- Study 11: point spreads on Polymarket. Laying points against taking points, and how often games are decided by one.
-- Read-only. Read-only role against production.  psql "$DATABASE_URL" -X -f spreads.sql
-- A Polymarket spread market is titled "Spread: <team> (-X.5)" with outcomes <team> / <other team>. Outcome 0
-- wins when the named team wins by more than X.5, so outcome 0 is laying the points and outcome 1 taking them.
-- Polymarket lists a ladder of alternate lines for both teams (the Bills-Texans NFL game on 2026-09-13 carried 35,
-- Bills -0.5 to -21.5 and Texans -1.5 to -21.5), so the named team is not always the pre-game favorite; this study
-- never assumes it is. Margin figures use games where both teams carry the same
-- line, so no favorite has to be known. Soccer spreads live under the match slug plus "-more-markets"; base_slug strips
-- it to reach the match's draw market. Pricing uses large-trade alert buys from 2026-04-02. Temp tables.
select now() as run_at;

create temp table sp as
select m.condition_id, m.event_slug, regexp_replace(m.event_slug, '-more-markets$', '') base_slug, m.category, m.game_start_time,
       mo.winning_outcome w, mo.resolved_at,
       substring(m.title from '^Spread: (.*) \(-[0-9.]+\)$') team, substring(m.title from '\(-([0-9.]+)\)$')::numeric line,
       case when m.category in ('NBA', 'Basketball', 'WNBA') then 'Basketball' when m.category in ('NFL', 'NCAAF') then 'Football'
            else m.category end sport
from markets m join market_outcomes mo on mo.condition_id = m.condition_id
where m.sports_market_type = 'spreads' and mo.winning_outcome in (0, 1) and m.game_start_time < timestamptz '2026-09-14'
  and m.category in ('NFL', 'NCAAF', 'NBA', 'Basketball', 'WNBA', 'Baseball', 'Hockey', 'Soccer')
  and m.title ~ '^Spread: .* \(-[0-9.]+\)$' and substring(m.title from '^Spread: (.*) \(-[0-9.]+\)$') = m.outcome_yes;

-- 1. Sample: settled spread markets by league category, games, lines per game, and the share of games that list
--    minus lines for both teams.
select category, count(*) markets, count(distinct event_slug) games, round(count(*)::numeric / count(distinct event_slug), 1) lines_per_game,
       count(*) filter (where line % 1 <> 0.5) not_half_point_lines,
       min(game_start_time)::date first_game, max(game_start_time)::date last_game
from sp group by rollup(1) order by 2 desc;
select sport, count(*) games, count(*) filter (where teams = 2) both_teams_listed,
       round(100.0*avg((teams = 2)::int), 1) both_teams_pct
from (select sport, event_slug, count(distinct team) teams from sp group by 1, 2) x group by 1 order by 2 desc;

-- 1b. League prefixes behind the category labels: games by event-slug prefix, the ten largest.
select category, split_part(event_slug, '-', 1) prefix, count(distinct event_slug) games
from sp group by 1, 2 order by 3 desc limit 10;

-- 2. Check: a named team that covered its spread must also have won its moneyline (the result market naming it).
create temp table ml as
select m.event_slug, m.outcome_yes o0, m.outcome_no o1, mo.winning_outcome w
from markets m join market_outcomes mo on mo.condition_id = m.condition_id
where m.sports_market_type = 'moneyline' and mo.winning_outcome in (0, 1)
  and m.category in ('NFL', 'NCAAF', 'NBA', 'Basketball', 'WNBA', 'Baseball', 'Hockey');
select s.sport, count(*) joined, count(*) filter (where s.w = 0) covered,
       count(*) filter (where s.w = 0 and ((l.o0 = s.team and l.w = 0) or (l.o1 = s.team and l.w = 1))) covered_and_won
from sp s join ml l on l.event_slug = s.event_slug and (l.o0 = s.team or l.o1 = s.team)
group by 1 order by 2 desc;

-- 3. Both teams listed at -1.5: neither covering means a one-run (one-goal) game, or a draw in soccer.
create temp table both15 as
select sport, category, event_slug, min(game_start_time) ko, count(distinct team) teams, sum((w = 0)::int) covered
from sp where line = 1.5 group by 1, 2, 3;
select sport, count(*) games, count(*) filter (where covered = 0) neither_covered,
       round(100.0*avg((covered = 0)::int), 1) decided_by_one_pct,
       round(100*1.959964*sqrt(avg((covered = 0)::int)::numeric*(1-avg((covered = 0)::int)::numeric)/count(*)), 2) half_width_pts,
       count(*) filter (where covered = 2) both_covered_check, min(ko)::date first_game, max(ko)::date last_game
from both15 where teams = 2 group by 1 order by 2 desc;

-- 4. Baseball one-run games by calendar month.
select to_char(date_trunc('month', ko), 'YYYY-MM') game_month, count(*) games, round(100.0*avg((covered = 0)::int), 1) one_run_pct
from both15 where teams = 2 and sport = 'Baseball' group by 1 order by 1;

-- 5. Soccer margins on matches listing both teams at -1.5 and at -2.5, with the match's draw market:
--    a draw, a one-goal win, a two-goal win, or a win by three or more.
create temp table draw_leg as
select m.event_slug, mo.winning_outcome w
from markets m join market_outcomes mo on mo.condition_id = m.condition_id
where m.category = 'Soccer' and m.sports_market_type = 'moneyline' and m.outcome_yes = 'Yes'
  and (m.group_item_title like 'Draw (%' or m.title like '%end in a draw%') and mo.winning_outcome in (0, 1);
create temp table soccer_m as
select base_slug event_slug,
       count(distinct team) filter (where line = 1.5) teams15, sum((w = 0)::int) filter (where line = 1.5) cov15,
       count(distinct team) filter (where line = 2.5) teams25, sum((w = 0)::int) filter (where line = 2.5) cov25
from sp where sport = 'Soccer' group by 1;
select count(*) matches,
       round(100.0*avg((d.w = 0)::int), 1) draw_pct,
       round(100.0*avg((d.w = 1 and s.cov15 = 0)::int), 1) one_goal_win_pct,
       round(100.0*avg((s.cov15 = 1 and s.cov25 = 0)::int), 1) two_goal_win_pct,
       round(100.0*avg((s.cov25 = 1)::int), 1) three_plus_win_pct,
       count(*) filter (where d.w = 0 and s.cov15 > 0) check_draw_but_covered
from soccer_m s join draw_leg d using (event_slug)
where s.teams15 = 2 and s.teams25 = 2;
select count(*) matches, round(100.0*avg((d.w = 0)::int), 1) draw_pct,
       round(100.0*avg((d.w = 1 and s.cov15 = 0)::int), 1) one_goal_win_pct,
       round(100.0*avg((s.cov15 = 1)::int), 1) two_plus_win_pct
from soccer_m s join draw_leg d using (event_slug) where s.teams15 = 2;

-- 6. Large buys on spread markets from April 2, 2026: laying the points (outcome 0) against taking them (outcome 1).
create temp table bb as
select w.id, w.condition_id, w.traded_at, w.price_num, w.usdc_notional_num, w.trader_id, s.sport, s.line,
       case when w.outcome_index = 0 then 'Laying points' else 'Taking points' end side,
       case when w.traded_at < s.game_start_time then 'Before the start' else 'In-play' end phase,
       (w.outcome_index = s.w)::int won
from whale_alerts w join sp s on s.condition_id = w.condition_id
where w.platform = 'polymarket' and w.side = 0 and w.traded_at >= date '2026-04-02' and w.traded_at < date '2026-09-14'
  and s.resolved_at > w.traded_at and w.price_num between 0.02 and 0.98 and w.outcome_index in (0, 1);
select count(*) buys, count(distinct condition_id) markets, count(distinct trader_id) wallets, round(sum(usdc_notional_num)/1e6, 1) notional_musd,
       round(100.0*avg((phase = 'In-play')::int), 1) in_play_pct, min(traded_at)::date first_buy, max(traded_at)::date last_buy
from bb;
-- 6b. League prefixes behind the large buys.
select b.sport, split_part(s.event_slug, '-', 1) prefix, count(*) buys, count(distinct b.condition_id) markets
from bb b join sp s using (condition_id) group by 1, 2 order by 3 desc limit 10;
select sport, side, count(*) buys, count(distinct condition_id) markets, round(sum(usdc_notional_num)/1e6, 1) notional_musd,
       round(avg(price_num)*100, 1) avg_price_c, round(avg(won)::numeric*100, 1) win_pct,
       round((avg(won)::numeric - avg(price_num))*100, 2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num - 1))/sum(usdc_notional_num))*100, 2) dollar_roi_pct
from bb group by rollup(1, 2) order by 1, 2;

-- 7. By phase and side.
select phase, side, count(*) buys, count(distinct condition_id) markets, round(avg(price_num)*100, 1) avg_price_c,
       round(avg(won)::numeric*100, 1) win_pct, round((avg(won)::numeric - avg(price_num))*100, 2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num - 1))/sum(usdc_notional_num))*100, 2) dollar_roi_pct
from bb group by 1, 2 order by 1, 2;

-- 8. By price band and side.
select side, case when price_num < 0.30 then 'a. under 30c' when price_num < 0.50 then 'b. 30-50c' when price_num < 0.70 then 'c. 50-70c' else 'd. 70c+' end band,
       count(*) buys, count(distinct condition_id) markets, round(avg(price_num)*100, 1) avg_price_c,
       round(avg(won)::numeric*100, 1) win_pct, round((avg(won)::numeric - avg(price_num))*100, 2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num - 1))/sum(usdc_notional_num))*100, 2) dollar_roi_pct
from bb group by 1, 2 order by 1, 2;

-- 9. Graded wallets from June 1, 2026: the grade each wallet held on the trade day.
create temp table bbg as
select b.*, case when gr.grade in ('S', 'A', 'B') then 'S, A and B' when gr.grade in ('D', 'F') then 'D and F' else 'other' end cohort
from bb b left join lateral (select tr.grade from trader_rankings tr where tr.trader_id = b.trader_id and tr.date <= b.traded_at::date
                             order by tr.date desc limit 1) gr on true
where b.traded_at >= date '2026-06-01';
select cohort, side, count(*) buys, count(distinct condition_id) markets, round(avg(price_num)*100, 1) avg_price_c,
       round(avg(won)::numeric*100, 1) win_pct, round((avg(won)::numeric - avg(price_num))*100, 2) edge_pts
from bbg where cohort <> 'other' group by 1, 2 order by 1, 2;

-- 10. Market-level export for the clustered bootstrap: sport and side, all sports by side, phase and side,
--     price band and side, and cohort and side.
\copy (select grp, condition_id, count(*) n, sum(won::numeric - price_num) sum_edge from (select sport || ' | ' || side as grp, condition_id, won, price_num from bb union all select 'All sports | ' || side, condition_id, won, price_num from bb union all select phase || ' | ' || side, condition_id, won, price_num from bb union all select case when price_num < 0.30 then 'a. under 30c' when price_num < 0.50 then 'b. 30-50c' when price_num < 0.70 then 'c. 50-70c' else 'd. 70c+' end || ' | ' || side, condition_id, won, price_num from bb union all select cohort || ' | ' || side, condition_id, won, price_num from bbg where cohort <> 'other') x group by 1, 2) to './spreads-market-edge.csv' with (format csv, header true)
