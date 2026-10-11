-- Section charts for /research/point-spreads-polymarket and /research/home-field-advantage-polymarket (#23663, epic
-- #23652): how the volume on recent games split between the moneyline, spreads and totals, by league.
-- Read-only, against the production read replica through scripts/prod-read.sh:
--   ./scripts/prod-read.sh docs/research-articles/verification/2026-10-11-sports-volume-by-league-charts.sql.txt   (in the 0xinsider repository)
-- Universe: game markets that started from 00:00 UTC on September 10 to 00:00 UTC on October 11, 2026 (the first 31 days
-- of the 2026 NFL season), with a 0xinsider page and 1,000 or more in Polymarket's reported volume. The predicate is the
-- one idx_market_live_stats_sitemap_live_sports carries, so the read is an index range scan on game_start_time.
-- Volume is market_live_stats.volume, the Gamma per-market volume the event page's "Volume by family" bar sums; Polymarket
-- counts it in shares traded (#22291). The league is the event slug's prefix (soccer by category); a game is the slug up
-- to its date, so a game's "-more-markets" and "-player-props" events count with it. NBA and NHL games in this window
-- are preseason games and the first days of the NHL season.
with g as (
  select case when category = 'Soccer' then 'soccer' else split_part(event_slug, '-', 1) end league,
         substring(event_slug from '^([a-z0-9]+-[a-z0-9]+-[a-z0-9]+-\d{4}-\d{2}-\d{2})') game,
         sports_market_type family, volume
  from market_live_stats
  where present and page_slug is not null and title is not null and title <> '' and game_start_time is not null
    and coalesce(volume, 0) >= 1000 and is_provider_sports_market(null::bigint, sports_market_type, category)
    and game_start_time >= timestamptz '2026-09-10' and game_start_time < timestamptz '2026-10-11'
)
select league, count(distinct game) games, count(*) markets,
       count(*) filter (where family = 'spreads') spread_markets,
       round(sum(volume)) volume,
       round(sum(volume) filter (where family = 'moneyline')) moneyline_volume,
       round(sum(volume) filter (where family = 'spreads')) spreads_volume,
       round(sum(volume) filter (where family = 'totals')) totals_volume,
       round(100 * sum(volume) filter (where family = 'moneyline') / sum(volume), 1) moneyline_pct,
       round(100 * sum(volume) filter (where family = 'spreads') / sum(volume), 1) spreads_pct,
       round(100 * sum(volume) filter (where family = 'totals') / sum(volume), 1) totals_pct
from g
where league in ('nfl', 'cfb', 'mlb', 'nba', 'wnba', 'nhl', 'soccer')
group by 1
order by sum(volume) desc;
