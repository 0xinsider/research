-- NBA favorite-longshot pricing study (#14060): the one-game breakdown used verbatim in the
-- article and the how-to-bet guide as NBA_EXAMPLE_GAME. Read-only, posthog_readonly, Neon
-- branch main. Direct query on markets.event_slug, not the nba_buys view in
-- nba-pricing.sql -- this counts every listed market for the event
-- (moneyline/spreads/totals/props), not large trades against them.
select now() as run_at;

-- 1. Total markets and volume for the event.
select count(*) total_markets, round(sum(volume)/1e6,2) total_volume_musd
from markets where event_slug = 'nba-nyk-sas-2026-06-13';

-- 2. By sports_market_type.
select coalesce(sports_market_type,'(unknown)') market_type, count(*) n, round(sum(volume)/1e6,2) volume_musd
from markets
where event_slug = 'nba-nyk-sas-2026-06-13'
group by 1 order by n desc;

-- 3. Player-prop markets (points/rebounds/assists), named as one figure in the article.
select coalesce(sports_market_type,'(unknown)') market_type, count(*) n
from markets
where event_slug = 'nba-nyk-sas-2026-06-13'
  and sports_market_type in ('points','rebounds','assists')
group by 1 order by 1;
