-- Section charts for /research/football-underdogs-polymarket (#23663, epic #23652): what the NFL and college football
-- boards carried in the first 31 days of the 2026 NFL season, and how a game's volume splits across market families.
-- Read-only, against the production read replica through scripts/prod-read.sh:
--   ./scripts/prod-read.sh docs/research-articles/verification/2026-10-11-football-underdogs-polymarket-charts.sql.txt   (in the 0xinsider repository)
-- Universe: NFL and college football game markets that started from 00:00 UTC on September 10 to 00:00 UTC on
-- October 11, 2026, with a 0xinsider page and 1,000 or more in Polymarket's reported volume (the predicate of
-- idx_market_live_stats_sitemap_live_sports, so the read is an index range scan on game_start_time). Volume is
-- market_live_stats.volume, the Gamma per-market volume the event page's "Volume by family" bar sums; Polymarket counts
-- it in shares traded (#22291). A game is the event slug up to its date, so "-player-props" and other derivative events
-- count with their game. Families are Polymarket's sportsMarketType; the eight largest by volume across both leagues
-- are named and the rest grouped.
with g as (
  select split_part(event_slug, '-', 1) league,
         substring(event_slug from '^([a-z0-9]+-[a-z0-9]+-[a-z0-9]+-\d{4}-\d{2}-\d{2})') game,
         coalesce(sports_market_type, '(none)') family, volume
  from market_live_stats
  where present and page_slug is not null and title is not null and title <> '' and game_start_time is not null
    and coalesce(volume, 0) >= 1000 and is_provider_sports_market(null::bigint, sports_market_type, category)
    and game_start_time >= timestamptz '2026-09-10' and game_start_time < timestamptz '2026-10-11'
    and split_part(event_slug, '-', 1) in ('nfl', 'cfb')
), top as (
  select family from g group by 1 order by sum(volume) desc limit 8
)
-- One row per league and family, and a league total (family "(all)") with its game count.
select league, coalesce(fam, '(all)') family, count(distinct game) games, count(*) markets, round(sum(volume)) volume,
       round(100 * sum(volume) / max(league_volume), 1) share_pct
from (
  select g.*, case when family in (select family from top) then family else '(other families)' end fam,
         sum(volume) over (partition by league) league_volume
  from g
) x
group by grouping sets ((league, fam), (league))
order by 1, (fam is not null), sum(volume) desc;
