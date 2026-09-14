-- Study 15 (#13943): esports first-map winners on Polymarket. How often the winner of Map 1 (CS2, Valorant) or
-- Game 1 (LoL, Dota 2) of a best-of-three series goes on to win the series, how often the series is swept 2-0,
-- and what a settlement cross-check between three independent markets on the same series shows. Read-only,
-- against production as a read-only role.
--   psql "$DATABASE_URL" -X -f esports-map1.sql
--
-- A series is Polymarket's `moneyline` market whose title carries "(BO3)", for event slugs prefixed cs2, val,
-- valorant, dota2 or lol (Counter-Strike, Valorant, Dota 2, League of Legends). Its two outcomes are the two
-- teams. Three more markets share the same event_slug: a `child_moneyline` "Map 1 Winner" or "Game 1 Winner",
-- a second one for map/game 2, and a `totals` "Games Total: O/U 2.5". A series counts only when all four
-- markets settled 0 or 1 (a cancellation settles 50-50 and is left out) and its moneyline volume was $100 or
-- more (excludes markets that never really traded).
select now() as run_at;

create temp table series as
select distinct on (event_slug) condition_id, event_slug, title, outcome_yes team0, outcome_no team1,
       game_start_time, volume, token_id_yes, token_id_no,
       case when split_part(event_slug, '-', 1) in ('val', 'valorant') then 'valorant'
            when split_part(event_slug, '-', 1) = 'cs2' then 'cs2'
            when split_part(event_slug, '-', 1) = 'dota2' then 'dota2'
            when split_part(event_slug, '-', 1) = 'lol' then 'lol' end as game
from markets
where sports_market_type = 'moneyline' and title ~ '\(BO3\)'
  and split_part(event_slug, '-', 1) in ('cs2', 'val', 'valorant', 'dota2', 'lol')
order by event_slug, volume desc nulls last;

create temp table map1 as
select distinct on (event_slug) event_slug, condition_id, outcome_yes, outcome_no
from markets
where sports_market_type = 'child_moneyline' and group_item_title ~ '^(Map|Game) 1 Winner$'
order by event_slug, volume desc nulls last;

create temp table map2 as
select distinct on (event_slug) event_slug, condition_id, outcome_yes, outcome_no
from markets
where sports_market_type = 'child_moneyline' and group_item_title ~ '^(Map|Game) 2 Winner$'
order by event_slug, volume desc nulls last;

create temp table tot as
select distinct on (event_slug) event_slug, condition_id
from markets
where sports_market_type = 'totals' and line = 2.5
order by event_slug, volume desc nulls last;

-- 1. Universe funnel by game: BO3 series found, settled, and with a settled Map/Game 1, Map/Game 2 and
--    Games Total market on the same event, before the volume floor.
select series.game, count(*) bo3_series,
  count(*) filter (where mo.winning_outcome in (0, 1)) series_settled,
  count(*) filter (where m1mo.winning_outcome in (0, 1)) has_map1,
  count(*) filter (where m2mo.winning_outcome in (0, 1)) has_map2,
  count(*) filter (where totmo.winning_outcome in (0, 1)) has_totals
from series
left join market_outcomes mo on mo.condition_id = series.condition_id
left join map1 on map1.event_slug = series.event_slug
left join market_outcomes m1mo on m1mo.condition_id = map1.condition_id
left join map2 on map2.event_slug = series.event_slug
left join market_outcomes m2mo on m2mo.condition_id = map2.condition_id
left join tot on tot.event_slug = series.event_slug
left join market_outcomes totmo on totmo.condition_id = tot.condition_id
group by 1 order by 1;

create temp table joined as
select series.game, series.event_slug, series.condition_id, series.title, series.team0, series.team1,
       series.game_start_time, series.volume, series.token_id_yes, series.token_id_no,
       (case when mo.winning_outcome = 0 then series.team0 else series.team1 end) as series_winner,
       (case when m1mo.winning_outcome = 0 then map1.outcome_yes else map1.outcome_no end) as map1_winner,
       (case when m2mo.winning_outcome = 0 then map2.outcome_yes else map2.outcome_no end) as map2_winner,
       (totmo.winning_outcome = 1) as swept
from series
join market_outcomes mo on mo.condition_id = series.condition_id and mo.winning_outcome in (0, 1)
join map1 on map1.event_slug = series.event_slug
join market_outcomes m1mo on m1mo.condition_id = map1.condition_id and m1mo.winning_outcome in (0, 1)
join map2 on map2.event_slug = series.event_slug
join market_outcomes m2mo on m2mo.condition_id = map2.condition_id and m2mo.winning_outcome in (0, 1)
join tot on tot.event_slug = series.event_slug
join market_outcomes totmo on totmo.condition_id = tot.condition_id and totmo.winning_outcome in (0, 1)
where series.volume >= 100;

-- 2. The counted universe: series with all four markets settled and $100 or more traded, by game, with dates.
select game, count(*) series, min(game_start_time)::date first_series, max(game_start_time)::date last_series,
       round(sum(volume)) volume_usd
from joined group by 1 order by 1;

-- 3. Settlement cross-check: a team that won map/game 1 and map/game 2 must hold the series, and winning maps
--    1 and 2 must mean the Games Total market settled Under 2.5 (swept). The reverse also must hold: any series
--    that did NOT sweep must have split map 1 and map 2 between the two teams.
select
  count(*) as series,
  count(*) filter (where map1_winner = map2_winner and series_winner = map1_winner and swept) as sweep_agrees,
  count(*) filter (where map1_winner = map2_winner and (series_winner <> map1_winner or not swept)) as sweep_disagrees,
  count(*) filter (where map1_winner <> map2_winner and not swept) as decider_agrees,
  count(*) filter (where map1_winner <> map2_winner and swept) as decider_disagrees
from joined;

-- 4. Any disagreement, for the record (expect zero rows).
select event_slug, title, team0, team1, series_winner, map1_winner, map2_winner, swept
from joined
where (map1_winner = map2_winner and (series_winner <> map1_winner or not swept))
   or (map1_winner <> map2_winner and swept)
limit 20;

-- 5. Headline rates by game: how often the map/game 1 winner took the series, and the sweep rate.
select game, count(*) n,
       count(*) filter (where map1_winner = series_winner) map1_winner_won_series,
       round(100.0 * count(*) filter (where map1_winner = series_winner) / count(*), 2) as map1_won_series_pct,
       count(*) filter (where swept) swept_n,
       round(100.0 * count(*) filter (where swept) / count(*), 2) as swept_pct
from joined group by 1 order by 1;

-- 6. Same, pooled across the four games.
select count(*) n,
       round(100.0 * count(*) filter (where map1_winner = series_winner) / count(*), 2) as map1_won_series_pct,
       round(100.0 * count(*) filter (where swept) / count(*), 2) as swept_pct
from joined;

-- 7. Series volume, for the market-size figure quoted in the article (all esports moneylines and the four-game
--    BO3 universe), from 2025-01-01.
select
  (select round(sum(m.volume)) from markets m join market_outcomes mo on mo.condition_id = m.condition_id
    where m.sports_market_type = 'moneyline' and m.category = 'Esports' and mo.winning_outcome in (0, 1)
      and m.game_start_time >= '2025-01-01') as all_esports_moneyline_volume_usd,
  (select round(sum(volume)) from joined) as counted_bo3_volume_usd,
  (select count(*) from markets m join market_outcomes mo on mo.condition_id = m.condition_id
    where m.sports_market_type = 'moneyline' and m.category = 'Esports' and mo.winning_outcome in (0, 1)
      and m.game_start_time >= '2025-01-01') as all_esports_moneyline_n;

-- 8. Export for the CLOB price pull and the analysis script.
\copy (select game, event_slug, condition_id, team0, team1, series_winner, map1_winner, map2_winner, swept, round(volume) volume_usd, token_id_yes, token_id_no, to_char(game_start_time at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') game_start_utc from joined order by game_start_time, event_slug) to 'esports-map1-series.csv' with csv header
