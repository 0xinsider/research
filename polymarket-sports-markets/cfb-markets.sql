-- College football guide: what Polymarket lists for a college football game in the 2026 season, where the money goes,
-- and each main market family's rules. Read-only, a read-only role against production.
--   psql "$DATABASE_URL" -X -f cfb-markets.sql
-- Universe: markets under a college football game slug (cfb-<away>-<home>-<date>, derivative slugs included) for games
-- from August 20 to 04:00 UTC on September 13, 2026. Volume is Polymarket's reported lifetime volume per market, USDC.
select now() as run_at;

create temp table cfb as
select m.condition_id, m.sports_market_type, m.volume, m.game_start_time, m.title, m.group_item_title, m.description,
       substring(m.event_slug from '^(cfb-[a-z0-9]+-[a-z0-9]+-\d{4}-\d{2}-\d{2})') game
from markets m
where m.event_slug ~ '^cfb-[a-z0-9]+-[a-z0-9]+-2026-(08|09)-\d{2}'
  and m.game_start_time >= timestamptz '2026-08-20' and m.game_start_time < timestamptz '2026-09-13 04:00';

-- 1. All games: count, markets and volume.
select count(distinct game) games, count(*) markets, round(sum(volume)) volume_usd from cfb;

-- 2. By market family: games listing it, markets, markets per listing game, volume and share of all volume.
select coalesce(sports_market_type, '(none)') family, count(distinct game) games, count(*) markets,
       round(count(*)::numeric / count(distinct game), 1) markets_per_game, round(sum(volume)) volume_usd,
       round(100 * sum(volume) / sum(sum(volume)) over (), 1) share_pct
from cfb group by 1 order by sum(volume) desc nulls last;

-- 3. The rules of the most-traded market in each main family, from games on September 10 to 12.
select distinct on (sports_market_type) sports_market_type family, title, replace(description, E'\n', ' ') description
from cfb where game_start_time >= timestamptz '2026-09-10'
  and sports_market_type in ('moneyline', 'spreads', 'totals', 'team_totals', 'first_half_spreads', 'first_half_moneyline',
                             'q1_spreads', 'q4_moneyline', 'anytime_touchdowns', 'team_touchdowns')
order by sports_market_type, volume desc nulls last;

-- 4. How wide the spread ladders run: the widest line, the 10th percentile line and lines of 30 points or more.
--    `line` is stored negative for the team giving points.
select min(line) widest_line, percentile_cont(0.1) within group (order by line) p10_line,
       count(*) filter (where line <= -30) lines_30_or_more, count(*) spread_lines
from markets where sports_market_type = 'spreads' and event_slug ~ '^cfb-'
  and game_start_time >= timestamptz '2026-08-20' and game_start_time < timestamptz '2026-09-13 04:00';
