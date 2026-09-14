-- Over/under recount by game (#13926). The first run (over-under.sql, query 3) counted every
-- settled totals market as one trial. Polymarket lists a ladder of total lines on most games, and every line on a
-- game settles on the same final score, so this run keeps the game on every row and exports one row per game for
-- over-under-by-game.py, which resamples games.
-- Read-only, a read-only role against production.
--   psql "$DATABASE_URL" -X -f over-under-by-game.sql
-- Universe: the first run's markets universe. A market counts when its sports_market_type is totals, its outcomes
-- are Over (outcome 0) and Under (outcome 1), its kickoff falls from 2026-04-02 to 2026-09-13 inclusive, and it
-- settled 0 or 1. The game is the market's event_slug.
select now() as run_at;

create temp table tot as
select m.condition_id, m.event_slug, coalesce(m.category, '(none)') sport, m.line, m.volume, mo.winning_outcome w,
       m.game_start_time
from markets m join market_outcomes mo on mo.condition_id = m.condition_id
where m.sports_market_type = 'totals' and m.outcome_yes = 'Over' and m.outcome_no = 'Under'
  and m.game_start_time >= timestamptz '2026-04-02' and m.game_start_time < timestamptz '2026-09-14'
  and mo.winning_outcome in (0, 1);

-- 1. By sport, as the first run counted it (every line one trial) and with the game count beside it.
select sport, count(*) markets, count(distinct event_slug) games, round(count(*)::numeric / count(distinct event_slug), 2) lines_per_game,
       round(100.0 * count(*) filter (where w = 1) / count(*), 1) under_pct_of_lines
from tot group by rollup(1) order by count(*) desc;

-- 2. Checks: markets without a recorded line, a line listed twice on one game, games whose lines are spread over
--    more than one kickoff time, markets without a reported volume, and games whose totals sit under two event slugs
--    (soccer totals live under a `<match>-more-markets` event; a match with totals under both would count twice).
select count(*) filter (where line is null) markets_without_line,
       (select count(*) from (select regexp_replace(event_slug, '-more-markets$', '') g from tot group by 1 having count(distinct event_slug) > 1) s) games_under_two_slugs,
       (select count(*) from (select event_slug, line from tot where line is not null group by 1, 2 having count(*) > 1) d) duplicate_game_lines,
       (select count(*) from (select event_slug from tot group by 1 having count(distinct game_start_time) > 1) k) games_with_two_kickoffs,
       count(*) filter (where volume is null) markets_without_volume
from tot;

-- 2b. Line kind: can a total push? A whole-number line can land exactly on the score.
select case when line is null then '(no line)' when line = floor(line) then 'whole number' else 'half point' end line_kind, count(*) markets
from tot group by 1 order by 2 desc;

-- 2c. How often each line settled Under, for the two sports whose lines are the same numbers from game to game. A
--     game lists a line once (query 2), so every game in a row counts once and the rows are binomial.
select sport, line, count(*) games, round(100.0 * count(*) filter (where w = 1) / count(*), 1) under_pct,
       round(100 * 1.959964 * sqrt((count(*) filter (where w = 1)::numeric / count(*)) * (1 - count(*) filter (where w = 1)::numeric / count(*)) / count(*)), 2) half_width_pts
from tot where sport in ('Soccer', 'Esports') and line is not null
group by 1, 2 having count(*) >= 100 order by 1, 2;

-- 3. One row per game. lines and unders count every settled line. The main line is the game's most-traded line by
--    Polymarket's reported lifetime volume. The middle rung is the median line of the ladder by line value: one line
--    when the count is odd, the two middle lines at half weight when it is even (lines without a recorded value are
--    left out of the ladder order).
\copy (with ranked as (select t.*, row_number() over (partition by event_slug order by volume desc nulls last, line nulls last, condition_id) volume_rank, row_number() over (partition by event_slug order by line, condition_id) ladder_rank, count(*) filter (where line is not null) over (partition by event_slug) laddered from tot t), games as (select event_slug, min(sport) sport, to_char(min(game_start_time) at time zone 'UTC', 'YYYY-MM-DD') game_date, count(*) lines, count(*) filter (where w = 1) unders, max(line) filter (where volume_rank = 1) main_line, max(w) filter (where volume_rank = 1) main_under, round(max(volume) filter (where volume_rank = 1)) main_volume_usd, round(avg(w) filter (where line is not null and laddered > 0 and ladder_rank between (laddered + 1) / 2 and laddered / 2 + 1), 2) middle_under from ranked group by event_slug) select * from games order by game_date, event_slug) to 'over-under-by-game.csv' with csv header

-- 4. The first run's buy-level edges, clustered by game. over-under-market-edge.csv holds one row per
--    group and market (buys and summed edge); this joins each market to its game so
--    over-under-by-game.py can resample games instead of markets. The temp table lives only in
--    this session.
create temp table edge (grp text, condition_id text, n integer, sum_edge numeric);
\copy edge from 'over-under-market-edge.csv' with csv header
select count(*) edge_rows, count(m.condition_id) joined_to_a_market, count(distinct m.event_slug) games from edge e left join markets m on m.condition_id = e.condition_id;
\copy (select e.grp, m.event_slug, sum(e.n) n, sum(e.sum_edge) sum_edge from edge e join markets m on m.condition_id = e.condition_id group by 1, 2 order by 1, 2) to 'over-under-game-edge.csv' with csv header
