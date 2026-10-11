-- Section charts for /research/soccer-draws-polymarket (#23665, epic #23652).
-- Read-only. Run on a Neon child branch of production (claude-18-23665-charts, forked about 12:11 UTC on
-- 2026-10-11) through scripts/neon-child-branch.sh, so the scans never touched the production compute:
--   ./scripts/neon-child-branch.sh query --name claude-18-23665-charts --statement-timeout 20min \
--     -f soccer-draws-charts-2026-10-11.sql
-- Output: soccer-draws-charts-2026-10-11-output.txt beside this file. The temp tables live only in the
-- session; nothing here writes to a table that existed before the run. Definitions follow
-- soccer-draws.sql: a match is three binary markets under one event, "Will <home> win on
-- <date>?", "Will <away> win on <date>?" and "Will <home> vs. <away> end in a draw?"; outcome 0 is Yes on every leg.
select now() as run_at, (select max(traded_at) from whale_alerts where traded_at > timestamptz '2026-10-09') latest_alert_on_branch;

-- 1. Out of sample. The draw-rate universe of query 2 (every settled draw leg, identified by title), for kickoffs
--    AFTER the study's window: 2026-09-14 to 2026-10-09 inclusive.
create temp table draw_new as
select m.condition_id, mo.winning_outcome w
from markets m left join market_outcomes mo on mo.condition_id = m.condition_id
where m.category = 'Soccer' and (m.group_item_title like 'Draw (%' or m.title like '%end in a draw%')
  and m.outcome_yes = 'Yes'
  and m.game_start_time >= timestamptz '2026-09-14' and m.game_start_time < timestamptz '2026-10-10';
select count(*) listed_draw_legs, count(*) filter (where w in (0, 1)) settled,
       round(100.0 * count(*) filter (where w = 0) / nullif(count(*) filter (where w in (0, 1)), 0), 1) draw_pct,
       round(100 * 1.959964 * sqrt((count(*) filter (where w = 0))::numeric / count(*) filter (where w in (0, 1))
             * (1 - (count(*) filter (where w = 0))::numeric / count(*) filter (where w in (0, 1))) / count(*) filter (where w in (0, 1))), 2) half_width_pts
from draw_new;

-- 2. Which leg settled Yes. Query 1's universe (typed moneyline legs with Yes/No outcomes, kickoffs 2026-04-02 to
--    2026-09-13, settled Yes or No), complete events only (one draw leg and two team legs). Home is the team named
--    first in the draw leg's title; home_unmatched counts events where neither team leg carries that name.
create temp table legs as
select m.condition_id, m.event_slug, m.title, m.group_item_title,
       case when (m.group_item_title like 'Draw (%' or m.title like '%end in a draw%') then 'draw' else 'team' end leg,
       mo.winning_outcome w
from markets m join market_outcomes mo on mo.condition_id = m.condition_id
where m.category = 'Soccer' and m.sports_market_type = 'moneyline' and m.outcome_yes = 'Yes' and m.outcome_no = 'No'
  and m.game_start_time >= timestamptz '2026-04-02' and m.game_start_time < timestamptz '2026-09-14'
  and mo.winning_outcome in (0, 1);
with home as (
  select event_slug, regexp_replace(split_part(title, ' vs. ', 1), '^Will ', '') home from legs where leg = 'draw'),
ev as (
  select l.event_slug,
         count(*) filter (where l.leg = 'draw') draws, count(*) filter (where l.leg = 'team') teams,
         count(*) filter (where l.w = 0) yes_legs,
         bool_or(l.leg = 'draw' and l.w = 0) drew,
         bool_or(l.leg = 'team' and l.w = 0 and l.group_item_title = h.home) home_won,
         bool_or(l.leg = 'team' and l.w = 0 and l.group_item_title <> h.home) away_won,
         count(*) filter (where l.leg = 'team' and l.group_item_title = h.home) team_named_home
  from legs l join home h using (event_slug) group by 1)
select count(*) complete_events,
       count(*) filter (where yes_legs = 0) no_yes, count(*) filter (where yes_legs = 1) one_yes,
       count(*) filter (where yes_legs = 2) two_yes, count(*) filter (where yes_legs = 3) three_yes,
       count(*) filter (where team_named_home = 0) home_unmatched,
       round(100.0 * avg(home_won::int) filter (where team_named_home = 1), 1) home_win_pct,
       round(100.0 * avg(drew::int) filter (where team_named_home = 1), 1) draw_pct,
       round(100.0 * avg(away_won::int) filter (where team_named_home = 1), 1) away_win_pct,
       count(*) filter (where team_named_home = 1) events_with_home
from ev where draws = 1 and teams = 2;

-- 3. Home win, draw and away win in the European cups against the five largest domestic leagues, every settled
--    match on record before 2026-09-14 (the draw-rate universe of query 3, which reads legs by title because older
--    legs carry no sports_market_type). Event-slug prefixes as query 3 names them: ucl Champions League, uel Europa
--    League, col Conference League; epl, lal, sea, bun, fl1 the Premier League, La Liga, Serie A, the Bundesliga and
--    Ligue 1. Complete events only, home as in query 2.
create temp table cup_legs as
select m.event_slug, split_part(m.event_slug, '-', 1) prefix, m.title, m.group_item_title,
       case when (m.group_item_title like 'Draw (%' or m.title like '%end in a draw%') then 'draw'
            when m.title like 'Will % win on %' then 'team' else 'other' end leg,
       mo.winning_outcome w
from markets m join market_outcomes mo on mo.condition_id = m.condition_id
where m.category = 'Soccer' and m.outcome_yes = 'Yes' and mo.winning_outcome in (0, 1)
  and (m.sports_market_type is null or m.sports_market_type = 'moneyline')
  and m.event_slug !~ '-(more-markets|halftime-result)$'
  and m.game_start_time is not null and m.game_start_time < timestamptz '2026-09-14'
  and (m.event_slug like 'ucl-%' or m.event_slug like 'uel-%' or m.event_slug like 'col-%' or m.event_slug like 'epl-%'
       or m.event_slug like 'lal-%' or m.event_slug like 'sea-%' or m.event_slug like 'bun-%' or m.event_slug like 'fl1-%');
with home as (
  select event_slug, regexp_replace(split_part(title, ' vs. ', 1), '^Will ', '') home from cup_legs where leg = 'draw'),
ev as (
  select l.event_slug, min(l.prefix) prefix,
         count(*) filter (where l.leg = 'draw') draws, count(*) filter (where l.leg = 'team') teams,
         count(*) filter (where l.w = 0) yes_legs,
         bool_or(l.leg = 'draw' and l.w = 0) drew,
         bool_or(l.leg = 'team' and l.w = 0 and l.group_item_title = h.home) home_won,
         bool_or(l.leg = 'team' and l.w = 0 and l.group_item_title <> h.home) away_won,
         count(*) filter (where l.leg = 'team' and l.group_item_title = h.home) team_named_home
  from cup_legs l join home h using (event_slug) group by 1)
select case when prefix in ('ucl', 'uel', 'col') then prefix else 'big5' end grp,
       count(*) complete_events, count(*) filter (where yes_legs = 1) one_yes, count(*) filter (where team_named_home <> 1) home_unmatched,
       round(100.0 * avg(home_won::int) filter (where team_named_home = 1 and yes_legs = 1), 1) home_win_pct,
       round(100.0 * avg(drew::int) filter (where team_named_home = 1 and yes_legs = 1), 1) draw_pct,
       round(100.0 * avg(away_won::int) filter (where team_named_home = 1 and yes_legs = 1), 1) away_win_pct,
       count(*) filter (where team_named_home = 1 and yes_legs = 1) events_read
from ev where draws = 1 and teams = 2
group by 1 order by 1;

-- 4. What the large-trade feed carried on soccer match results in the 30 days to the run: every whale_alerts row
--    (buys and sells) from 2026-09-11 to 2026-10-10 inclusive on a soccer moneyline leg with Yes/No outcomes, by
--    leg (the draw against a team to win) and the outcome traded.
select case when (m.group_item_title like 'Draw (%' or m.title like '%end in a draw%') then 'draw' else 'team' end leg,
       case when w.outcome_index = 0 then 'Yes' else 'No' end outcome,
       count(*) trades, count(*) filter (where w.side = 0) buys,
       round(sum(w.usdc_notional_num) / 1e6, 2) notional_musd, count(distinct m.event_slug) matches
from whale_alerts w
join markets m on m.condition_id = w.condition_id
where w.platform = 'polymarket' and w.traded_at >= timestamptz '2026-09-11' and w.traded_at < timestamptz '2026-10-11'
  and m.category = 'Soccer' and m.sports_market_type = 'moneyline' and m.outcome_yes = 'Yes' and m.outcome_no = 'No'
group by rollup(1, 2) order by 1, 2;
