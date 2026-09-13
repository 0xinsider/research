-- Study 13: NRFI on Polymarket. How often no run scores in the first inning of an MLB game, how the market's two
-- formats resolve, and the market-level export the price and linescore scripts read. Read-only, a read-only role
-- against production.  psql "$DATABASE_URL" -X -f nrfi.sql
-- Universe: every MLB first-inning run market (sports_market_type 'nrfi', event slug 'mlb-...'), settled 0 or 1, for
-- games that started before 00:00 UTC on September 13, 2026. A canceled game settles 50-50 and is left out.
-- Two formats. Until April 2, 2026 the market was titled "NRFI: <away> vs. <home>" and resolved Yes when NO run
-- scored; from April 2 it is titled "Will there be a run scored in the first inning?: <away> vs. <home>" and resolves
-- Yes ("Yes Run" on eight markets) when a run scores. Each market's own description decides which way it is read.
select now() as run_at;

create temp table nrfi_all as
select m.condition_id, m.event_slug, m.title, m.game_start_time, m.closed, m.volume, m.token_id_yes, m.token_id_no,
       mo.winning_outcome w,
       case when m.description ~ 'resolve to ["“]Yes( Run)?["”] if no runs are scored' then 'yes_is_no_run'
            when m.description ~ 'resolve to ["“]Yes( Run)?["”] if at least one run is scored' then 'yes_is_run' end fmt
from markets m left join market_outcomes mo on mo.condition_id = m.condition_id
where m.sports_market_type = 'nrfi' and m.event_slug like 'mlb-%';

-- 1. Formats: what "Yes" means in each market's description, by title format, with the date range and settled count.
select case when title like 'NRFI:%' then 'NRFI: <away> vs. <home>' when title like 'Will there be a run scored in the first inning?%' then 'Will there be a run scored in the first inning?' else title end title_format,
       coalesce(fmt, 'unclassified') yes_means, count(*) markets, count(*) filter (where w in (0, 1)) settled_0_or_1,
       count(*) filter (where w not in (0, 1)) settled_other, min(game_start_time)::date first_game, max(game_start_time)::date last_game
from nrfi_all group by 1, 2 order by 5;

-- 2. Coverage: closed markets for games that started before September 11 with and without a settled outcome row.
select count(*) closed_markets, count(*) filter (where w in (0, 1)) settled_0_or_1, count(*) filter (where w is null) no_outcome_row,
       count(*) filter (where w is not null and w not in (0, 1)) settled_other,
       round(100.0 * count(*) filter (where w in (0, 1)) / count(*), 1) settled_pct
from nrfi_all where closed and game_start_time < timestamptz '2026-09-11';

create temp table nrfi as
select condition_id, event_slug, title, game_start_time, volume, token_id_yes, token_id_no, w, fmt,
       case when fmt = 'yes_is_no_run' then (w = 0)::int when fmt = 'yes_is_run' then (w = 1)::int end no_run
from nrfi_all where w in (0, 1) and fmt is not null and game_start_time < timestamptz '2026-09-13';

-- 3. No run in the first inning, by season, with a binomial half-width and the date range.
select case when game_start_time < timestamptz '2026-01-01' then '2025 (September)' else '2026' end season, count(*) games,
       sum(no_run) no_run_games, round(100.0 * avg(no_run), 1) no_run_pct,
       round(100 * 1.959964 * sqrt(avg(no_run)::numeric * (1 - avg(no_run)::numeric) / count(*)), 2) half_width_pts,
       min(game_start_time)::date first_game, max(game_start_time)::date last_game
from nrfi group by 1 order by 1;

-- 4. All games together.
select count(*) games, sum(no_run) no_run_games, round(100.0 * avg(no_run), 1) no_run_pct,
       round(100 * 1.959964 * sqrt(avg(no_run)::numeric * (1 - avg(no_run)::numeric) / count(*)), 2) half_width_pts
from nrfi;

-- 5. By calendar month of the game, US Eastern.
select to_char(game_start_time at time zone 'America/New_York', 'YYYY-MM') game_month, count(*) games, round(100.0 * avg(no_run), 1) no_run_pct,
       round(100 * 1.959964 * sqrt(avg(no_run)::numeric * (1 - avg(no_run)::numeric) / count(*)), 2) half_width_pts
from nrfi group by 1 order by 1;

-- 6. By format, the check that the two readings give similar rates.
select fmt, count(*) games, round(100.0 * avg(no_run), 1) no_run_pct from nrfi group by 1 order by 1;

-- 7. Money traded on these markets (Polymarket's reported volume, USDC).
select case when game_start_time < timestamptz '2026-01-01' then '2025 (September)' else '2026' end season, count(*) markets,
       round(sum(volume)) volume_usd, round(avg(volume)) avg_volume_usd, round(percentile_cont(0.5) within group (order by volume)::numeric) median_volume_usd
from nrfi group by 1 order by 1;

-- 8. Large-trade alert buys on these markets from April 2, 2026, by the side bought: too few for a pricing read.
select case when (n.fmt = 'yes_is_no_run') = (wa.outcome_index = 0) then 'No run' else 'Run scored' end side_bought, count(*) buys,
       count(distinct wa.condition_id) markets
from whale_alerts wa join nrfi n on n.condition_id = wa.condition_id
where wa.side = 0 and wa.traded_at >= timestamptz '2026-04-02' and wa.outcome_index in (0, 1)
group by 1 order by 1;

-- 9. Export for nrfi-prices.py and nrfi-linescores.py.
\copy (select condition_id, event_slug, regexp_replace(title, '^(NRFI: |Will there be a run scored in the first inning\?: )', '') matchup, fmt, token_id_yes, token_id_no, to_char(game_start_time at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') game_start_utc, w winning_outcome from nrfi order by game_start_time, event_slug) to 'nrfi-markets.csv' with csv header
