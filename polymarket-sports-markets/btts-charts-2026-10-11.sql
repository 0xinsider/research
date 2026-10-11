-- Section charts for /research/both-teams-to-score-polymarket (#23665, epic #23652).
-- Read-only. Run on a Neon child branch of production (claude-18-23665-charts, forked about 12:11 UTC on
-- 2026-10-11) through scripts/neon-child-branch.sh, so the scans never touched the production compute:
--   ./scripts/neon-child-branch.sh query --name claude-18-23665-charts --statement-timeout 20min \
--     -f btts-charts-2026-10-11.sql
-- Output: btts-charts-2026-10-11-output.txt beside this file. The temp tables live only in
-- the session; nothing here writes to a table that existed before the run. Definitions follow
-- btts-halftime.sql: a both teams to score market has sports_market_type both_teams_to_score
-- and outcomes Yes (0) and No (1), and lives under the match's event slug plus "-more-markets".
select now() as run_at, (select max(traded_at) from whale_alerts where traded_at > timestamptz '2026-10-09') latest_alert_on_branch;

-- Every both teams to score market with a kickoff from 2025-10-01 (the first settled one kicked off 2025-10-24) to
-- 2026-10-09, whatever its result.
create temp table btts_all as
select m.condition_id, regexp_replace(m.event_slug, '-more-markets$', '') base_slug, m.game_start_time,
       mo.winning_outcome w
from markets m left join market_outcomes mo on mo.condition_id = m.condition_id
where m.sports_market_type = 'both_teams_to_score' and m.outcome_yes = 'Yes' and m.outcome_no = 'No'
  and m.game_start_time >= timestamptz '2025-10-01' and m.game_start_time < timestamptz '2026-10-10';

-- 1. How the study window's markets settled (kickoffs before 2026-09-14): Yes, No, and every other recorded state,
--    with the market_outcomes value as stored (no row: not yet recorded).
select coalesce(w::text, '(no outcome row)') winning_outcome, count(*) markets
from btts_all where game_start_time < timestamptz '2026-09-14' group by 1 order by 2 desc;

-- 2. By kickoff month (UTC), the study window, settled Yes or No.
select to_char(date_trunc('month', game_start_time), 'YYYY-MM') kickoff_month, count(*) markets,
       round(100.0 * count(*) filter (where w = 0) / count(*), 1) yes_pct
from btts_all where game_start_time < timestamptz '2026-09-14' and w in (0, 1) group by 1 order by 1;

-- 3. Out of sample: kickoffs 2026-09-14 to 2026-10-09 inclusive.
select count(*) listed, count(*) filter (where w in (0, 1)) settled,
       round(100.0 * count(*) filter (where w = 0) / nullif(count(*) filter (where w in (0, 1)), 0), 1) yes_pct,
       round(100 * 1.959964 * sqrt((count(*) filter (where w = 0))::numeric / count(*) filter (where w in (0, 1))
             * (1 - (count(*) filter (where w = 0))::numeric / count(*) filter (where w in (0, 1))) / count(*) filter (where w in (0, 1))), 2) half_width_pts
from btts_all where game_start_time >= timestamptz '2026-09-14';

-- 4. Both teams to score against the full-match Over/Under 2.5 on the same match, the study window, as a 2x2 count
--    (query 4 of the September run printed only the shares). The game total lives under the match's own event slug.
select case when b.w = 0 then 'both scored' else 'not both' end btts,
       count(*) matches, count(*) filter (where o.w = 0) over25, count(*) filter (where o.w = 1) under25
from btts_all b
join lateral (
  select mo.winning_outcome w from markets m join market_outcomes mo on mo.condition_id = m.condition_id
  where m.event_slug = b.base_slug and m.category = 'Soccer' and m.sports_market_type = 'totals' and m.line = 2.5
    and m.outcome_yes = 'Over' and mo.winning_outcome in (0, 1)
  limit 1) o on true
where b.game_start_time < timestamptz '2026-09-14' and b.w in (0, 1)
group by rollup(1) order by 1;

-- 5. Which side-market families Polymarket listed on the soccer matches of the 30 days to the run: matches with a
--    kickoff from 2026-09-11 to 2026-10-10 inclusive and a draw leg (the result markets), and how many of them carry
--    each family under the match's event slug or its "-more-markets" / "-halftime-result" event (side markets are
--    matched by slug, whatever their category).
create temp table soccer_month as
select regexp_replace(m.event_slug, '-(more-markets|halftime-result)$', '') base_slug, m.sports_market_type, m.title,
       m.group_item_title, m.category
from markets m
where m.event_slug is not null
  and m.game_start_time >= timestamptz '2026-09-11' and m.game_start_time < timestamptz '2026-10-11';
with matches as (
  select distinct base_slug from soccer_month
  where category = 'Soccer' and sports_market_type = 'moneyline' and (group_item_title like 'Draw (%' or title like '%end in a draw%'))
select coalesce(s.sports_market_type, '(none)') family, count(distinct s.base_slug) matches
from soccer_month s join matches using (base_slug)
group by 1 order by 2 desc;
