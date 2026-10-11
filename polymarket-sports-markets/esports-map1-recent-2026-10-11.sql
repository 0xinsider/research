-- Section charts for /research/esports-first-map-winner-polymarket (#23687, epic #23652): what the four esports
-- boards' games held over the 30 days before the run, and what the large-trade feed caught on them.
-- Read-only, against the production read replica through scripts/prod-read.sh (BEGIN READ ONLY, statement_timeout
-- 60s, ROLLBACK), one statement per call, on 2026-10-11 from 13:37:20 to 13:37:29 UTC. No row was written.
--   ./scripts/prod-read.sh <one statement below>
-- Window: games whose listed start fell from 00:00 UTC on September 11 to 00:00 UTC on October 11, 2026.
-- A game title is the event slug's prefix (cs2, val or valorant, dota2, lol), as in the September 14 study
-- (esports-map1.sql). A series is an event with a moneyline market; its format is the
-- "(BO1)", "(BO3)" or "(BO5)" in that market's title.
-- Query 1 reads market_live_stats with the predicate idx_market_live_stats_sitemap_live_sports carries (a market
-- with a 0xinsider page and 1,000 or more in Polymarket's reported volume), so it is an index range scan on
-- game_start_time. Volume is market_live_stats.volume, the Gamma per-market volume the event page sums; Polymarket
-- counts it in shares traded (#22291), so the shares below compare families, not dollars. child_moneyline is a
-- "Map N Winner" or "Game N Winner" market; totals is "Games Total"; other is every remaining family (handicaps,
-- kill and round totals, props).
-- Query 2 reads the large-trade feed (whale_alerts): every Polymarket BUY (side = 0) in the Esports category that
-- filled in the same 30 days (by the fill time, not the game's start) on one of the four games, by the family of the
-- market it bought. The feed's smallest esports buy in the window is $10,000 (min_usd).

select now() as run_at_utc;
-------------------------------
 2026-10-11 13:37:20.818038+00
(1 row)

-- 1. Series, formats and volume by market family, by game.
with s as (
  select case split_part(event_slug, '-', 1) when 'val' then 'valorant' else split_part(event_slug, '-', 1) end game,
         event_slug, sports_market_type family, title, volume
  from market_live_stats
  where present and page_slug is not null and title is not null and title <> '' and game_start_time is not null
    and coalesce(volume, 0) >= 1000 and is_provider_sports_market(null::bigint, sports_market_type, category)
    and game_start_time >= timestamptz '2026-09-11' and game_start_time < timestamptz '2026-10-11'
    and split_part(event_slug, '-', 1) in ('cs2', 'val', 'valorant', 'dota2', 'lol')
)
select coalesce(game, 'all four') game,
       count(distinct event_slug) filter (where family = 'moneyline') series,
       count(distinct event_slug) filter (where family = 'moneyline' and title ~ '\(BO1\)') bo1,
       count(distinct event_slug) filter (where family = 'moneyline' and title ~ '\(BO3\)') bo3,
       count(distinct event_slug) filter (where family = 'moneyline' and title ~ '\(BO5\)') bo5,
       count(distinct event_slug) filter (where family = 'child_moneyline') with_map_market,
       count(distinct event_slug) filter (where family = 'totals') with_totals,
       count(*) markets,
       round(sum(volume)) volume,
       round(sum(volume) filter (where family = 'moneyline')) moneyline_volume,
       round(sum(volume) filter (where family = 'child_moneyline')) map_winner_volume,
       round(sum(volume) filter (where family = 'totals')) totals_volume,
       round(sum(volume) filter (where family is null or family not in ('moneyline', 'child_moneyline', 'totals'))) other_volume,
       round(100 * sum(volume) filter (where family = 'moneyline') / sum(volume), 1) moneyline_pct,
       round(100 * sum(volume) filter (where family = 'child_moneyline') / sum(volume), 1) map_winner_pct,
       round(100 * sum(volume) filter (where family = 'totals') / sum(volume), 1) totals_pct
from s
group by rollup (game)
order by game nulls last;
----------+--------+-----+------+-----+-----------------+-------------+---------+-----------+------------------+-------------------+---------------+--------------+---------------+----------------+------------
 all four |   1936 | 326 | 1469 | 141 |            1417 |         433 |    6301 | 730716034 |        331779179 |         370285037 |       4067200 |     24584618 |          45.4 |           50.7 |        0.6
 cs2      |   1317 | 194 | 1108 |  15 |             959 |         224 |    3850 | 267374051 |        163668980 |          89271484 |       1344850 |     13088738 |          61.2 |           33.4 |        0.5
 dota2    |    233 |   0 |  226 |   7 |             229 |          62 |     867 | 184175259 |         55021446 |         126345147 |        346371 |      2462295 |          29.9 |           68.6 |        0.2
 lol      |    318 | 132 |   76 | 110 |             178 |         120 |    1324 | 241152776 |         89231850 |         142807800 |       2272945 |      6840181 |          37.0 |           59.2 |        0.9
 valorant |     68 |   0 |   59 |   9 |              51 |          27 |     260 |  38013948 |         23856903 |          11860606 |        103034 |      2193404 |          62.8 |           31.2 |        0.3
(5 rows)

select now() as run_at_utc;
-------------------------------
 2026-10-11 13:37:29.798825+00
(1 row)

-- 2. The large-trade feed's esports buys in the window, by game and by the family of the market bought.
select coalesce(g.game, 'all four') game, count(*) buys, round(sum(g.usd) / 1e6, 2) usd_m,
       count(*) filter (where g.family = 'moneyline') on_series_moneyline,
       count(*) filter (where g.family = 'child_moneyline') on_map_or_game_winner,
       count(*) filter (where g.family is distinct from 'moneyline' and g.family is distinct from 'child_moneyline') on_other,
       round(min(g.usd)) min_usd,
       count(distinct g.event_slug) series
from (
  select case split_part(m.event_slug, '-', 1) when 'val' then 'valorant' else split_part(m.event_slug, '-', 1) end game,
         m.event_slug, m.sports_market_type family, w.usdc_notional_num usd
  from whale_alerts w
  join markets m on m.condition_id = w.condition_id
  where w.platform = 'polymarket' and w.side = 0 and w.category = 'Esports'
    and w.traded_at >= timestamptz '2026-09-11' and w.traded_at < timestamptz '2026-10-11'
    and split_part(m.event_slug, '-', 1) in ('cs2', 'val', 'valorant', 'dota2', 'lol')
) g
group by rollup (g.game)
order by g.game nulls last;
----------+------+-------+---------------------+-----------------------+----------+---------+--------
 cs2      |  854 | 21.28 |                 707 |                    86 |       61 |   10000 |    160
 dota2    |  357 |  5.57 |                 123 |                   228 |        6 |   10000 |     68
 lol      |  680 | 12.99 |                 325 |                   337 |       18 |   10000 |     81
 valorant |  171 |  4.27 |                 147 |                     8 |       16 |   10000 |     27
 all four | 2062 | 44.12 |                1302 |                   659 |      101 |   10000 |    336
(5 rows)
