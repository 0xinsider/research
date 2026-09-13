-- MLB guide: what Polymarket lists for an MLB game in 2026, where the money goes, and each market family's rules.
-- Read-only. Read-only role against production.  psql "$DATABASE_URL" -X -f mlb-markets.sql
-- Universe: markets under a regular MLB game slug (mlb-<away>-<home>-<date>, derivative slugs such as
-- -first-five-winner included) for games from March 25 to September 12, 2026. Volume is Polymarket's reported
-- lifetime volume for each market, in USDC.
select now() as run_at;

create temp table mlb as
select m.condition_id, m.sports_market_type, m.volume, m.game_start_time, m.title, m.group_item_title, m.description,
       substring(m.event_slug from '^(mlb-[a-z]+-[a-z]+-\d{4}-\d{2}-\d{2})') game
from markets m
where m.category = 'Baseball' and m.event_slug ~ '^mlb-[a-z]+-[a-z]+-2026-\d{2}-\d{2}'
  and m.game_start_time >= timestamptz '2026-03-25' and m.game_start_time < timestamptz '2026-09-13';

-- 1. All games: count and volume.
select count(distinct game) games, count(*) markets, round(sum(volume)) volume_usd from mlb;

-- 2. By market family: games listing it, markets, markets per listing game, volume and share of all volume, first game.
select coalesce(sports_market_type, '(none)') family, count(distinct game) games, count(*) markets,
       round(count(*)::numeric / count(distinct game), 1) markets_per_game, round(sum(volume)) volume_usd,
       round(100 * sum(volume) / sum(sum(volume)) over (), 1) share_pct, min(game_start_time)::date first_game
from mlb group by 1 order by sum(volume) desc nulls last;

-- 3. The rules of one market per family, from games on September 10 to 12 (the most-traded market of each family).
select distinct on (sports_market_type) sports_market_type family, title, group_item_title, replace(description, E'\n', ' ') description
from mlb where game_start_time >= timestamptz '2026-09-10' and sports_market_type is not null
order by sports_market_type, volume desc nulls last;
