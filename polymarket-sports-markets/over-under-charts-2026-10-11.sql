-- Section charts for /research/over-under-polymarket-sports (#23665, epic #23652).
-- Read-only. Run on a Neon child branch of production (claude-18-23665-charts, forked about 12:11 UTC on
-- 2026-10-11) through scripts/neon-child-branch.sh, so the scans never touched the production compute:
--   ./scripts/neon-child-branch.sh query --name claude-18-23665-charts --statement-timeout 20min \
--     -f over-under-charts-2026-10-11.sql
-- Output: over-under-charts-2026-10-11-output.txt beside this file. The temp table lives only in
-- the session; nothing here writes to a table that existed before the run.
select now() as run_at, (select max(traded_at) from whale_alerts where traded_at > timestamptz '2026-10-09') latest_alert_on_branch;

-- 1. Out of sample. The September 14 recount's markets universe (over-under-by-game.sql), for
--    kickoffs AFTER its window: 2026-09-14 to 2026-10-09 inclusive. A game total is a market of type totals with
--    outcomes Over (0) and Under (1); a game lists a line once, so each row counts a game once.
create temp table tot_new as
select m.condition_id, m.event_slug, coalesce(m.category, '(none)') sport, m.line, mo.winning_outcome w
from markets m left join market_outcomes mo on mo.condition_id = m.condition_id
where m.sports_market_type = 'totals' and m.outcome_yes = 'Over' and m.outcome_no = 'Under'
  and m.game_start_time >= timestamptz '2026-09-14' and m.game_start_time < timestamptz '2026-10-10';

-- 1a. Coverage: listed lines in the new window, and how many have settled Over or Under.
select count(*) listed_lines, count(*) filter (where w in (0, 1)) settled_lines,
       count(distinct event_slug) filter (where w in (0, 1)) settled_games
from tot_new;

-- 1b. The soccer and esports lines, as recount query 2c counts them, on the new window.
select sport, line, count(*) games, round(100.0 * count(*) filter (where w = 1) / count(*), 1) under_pct,
       round(100 * 1.959964 * sqrt((count(*) filter (where w = 1)::numeric / count(*)) * (1 - count(*) filter (where w = 1)::numeric / count(*)) / count(*)), 2) half_width_pts
from tot_new where w in (0, 1) and sport in ('Soccer', 'Esports') and line is not null
group by 1, 2 having count(*) >= 100 order by 1, 2;

-- 2. What the large-trade feed carried on game totals in the 30 days to the run: every whale_alerts row (buys and
--    sells, the feed's own record) from 2026-09-11 to 2026-10-10 inclusive on a Polymarket game total, by the
--    market's sport and the outcome traded.
select coalesce(m.category, '(none)') sport,
       count(*) trades,
       count(*) filter (where w.outcome_index = 0) over_trades,
       count(*) filter (where w.outcome_index = 1) under_trades,
       count(*) filter (where w.side = 0) buys,
       round(sum(w.usdc_notional_num) / 1e6, 2) notional_musd,
       count(distinct m.event_slug) games
from whale_alerts w
join markets m on m.condition_id = w.condition_id
where w.platform = 'polymarket' and w.traded_at >= timestamptz '2026-09-11' and w.traded_at < timestamptz '2026-10-11'
  and m.sports_market_type = 'totals' and m.outcome_yes = 'Over' and m.outcome_no = 'Under'
group by rollup(1) order by 2 desc;
