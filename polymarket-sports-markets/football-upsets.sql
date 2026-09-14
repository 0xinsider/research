-- Study 14: football upsets on Polymarket. How often NFL and college football underdogs win, and the game-level
-- export the kickoff price and scoreboard scripts read. Read-only, a read-only role against production.
--   psql "$DATABASE_URL" -X -f football-upsets.sql
-- Universe: one settled full-game moneyline per NFL or college football game (slug prefixes nfl, cfb) whose title
-- lists its two outcomes in outcome order, "<outcome 0> vs. <outcome 1>", settled 0 or 1 (a tie or cancellation
-- settles 50-50 and is left out), for games that started before 04:00 UTC on September 13, 2026. The export calls
-- outcome 0 `away` after Polymarket's usual title convention. The convention has exceptions: the scoreboard match
-- found 111 NFL titles (110 away from neutral sites) and 3 college titles (all at neutral sites) naming ESPN's home
-- team first, so the analysis takes the home team from ESPN.
select now() as run_at;

create temp table fb as
select distinct on (m.event_slug) m.event_slug, m.condition_id, split_part(m.event_slug, '-', 1) league,
       m.outcome_yes away, m.outcome_no home, mo.winning_outcome w, m.game_start_time, m.token_id_yes, m.token_id_no,
       m.title, m.volume
from markets m join market_outcomes mo on mo.condition_id = m.condition_id
where m.sports_market_type = 'moneyline' and split_part(m.event_slug, '-', 1) in ('nfl', 'cfb')
  and mo.winning_outcome in (0, 1) and m.outcome_yes <> 'Yes' and m.game_start_time < timestamptz '2026-09-13 04:00'
  and regexp_replace(m.title, '^[^:]+: ', '') ~ ('^' || regexp_replace(m.outcome_yes, '([.*+?^${}()|\[\]\\])', '\\\1', 'g')
      || ' vs\.? ' || regexp_replace(m.outcome_no, '([.*+?^${}()|\[\]\\])', '\\\1', 'g') || ' ?$')
order by m.event_slug, m.volume desc nulls last;

-- 1. Games by league and calendar year, with the date range and Polymarket's reported moneyline volume.
select league, extract(year from game_start_time)::int game_year, count(*) games, min(game_start_time)::date first_game,
       max(game_start_time)::date last_game, round(sum(volume)) volume_usd
from fb group by 1, 2 order by 1, 2;

-- 2. Coverage: closed NFL and college football moneylines for games before September 11, 2026, with and without a
--    settled outcome row (two-team titles only).
select split_part(m.event_slug, '-', 1) league, count(*) closed_markets,
       count(*) filter (where mo.winning_outcome in (0, 1)) settled_0_or_1, count(*) filter (where mo.condition_id is null) no_outcome_row,
       count(*) filter (where mo.winning_outcome is not null and mo.winning_outcome not in (0, 1)) settled_other
from markets m left join market_outcomes mo on mo.condition_id = m.condition_id
where m.sports_market_type = 'moneyline' and split_part(m.event_slug, '-', 1) in ('nfl', 'cfb') and m.closed
  and m.outcome_yes <> 'Yes' and m.game_start_time < timestamptz '2026-09-11'
group by 1 order by 1;

-- 3. Export for football-scoreboard.py and football-prices.py.
\copy (select condition_id, event_slug, league, away, home, token_id_yes away_token, token_id_no home_token, to_char(game_start_time at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') game_start_utc, w winning_outcome, round(volume) volume_usd from fb order by game_start_time, event_slug) to 'football-games.csv' with csv header
