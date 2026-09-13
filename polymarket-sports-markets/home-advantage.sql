-- Study 12: home advantage on Polymarket. How often home teams win, by league, and what large bets on the home and
-- away sides paid. Read-only. Read-only role against production.  psql "$DATABASE_URL" -X -f home-advantage.sql
-- Home team. US leagues (NFL, NBA, MLB, NHL, WNBA, college football) title a game "<away> vs. <home>" with the away
-- team as the first outcome; the Gamma API marked the second outcome as home in 281 of 300 sampled events and the
-- first in none (the other 19 carry no ordering): see home-ordering-output.txt; 200 of 200 soccer matches sampled the same way agree. Soccer titles a
-- match "<home> vs. <away>"; the home team is the first team named in the match's draw market, the same side Gamma
-- marks as home. Results are market results; pricing uses large-trade alert buys from 2026-04-02. Temp tables.
select now() as run_at;

-- US leagues: one full-game moneyline per game whose title lists the two outcomes in order.
create temp table us as
select distinct on (m.event_slug) m.event_slug, m.condition_id, split_part(m.event_slug, '-', 1) league,
       m.outcome_yes away, m.outcome_no home, mo.winning_outcome w, mo.resolved_at, m.game_start_time, m.title
from markets m join market_outcomes mo on mo.condition_id = m.condition_id
where m.sports_market_type = 'moneyline' and split_part(m.event_slug, '-', 1) in ('nba', 'nfl', 'mlb', 'nhl', 'wnba', 'cfb')
  and mo.winning_outcome in (0, 1) and m.outcome_yes <> 'Yes' and m.game_start_time < timestamptz '2026-09-14'
  and m.title !~* '(all-star|4 nations)'
  and regexp_replace(m.title, '^[^:]+: ', '') ~ ('^' || regexp_replace(m.outcome_yes, '([.*+?^${}()|\[\]\\])', '\\\1', 'g')
      || ' vs\.? ' || regexp_replace(m.outcome_no, '([.*+?^${}()|\[\]\\])', '\\\1', 'g') || ' ?$')
order by m.event_slug, m.volume desc nulls last;

-- 1. US leagues: home win rate with a binomial half-width, and the date range.
select league, count(*) games, round(100.0*avg((w = 1)::int), 1) home_win_pct,
       round(100*1.959964*sqrt(avg((w = 1)::int)::numeric*(1-avg((w = 1)::int)::numeric)/count(*)), 2) half_width_pts,
       min(game_start_time)::date first_game, max(game_start_time)::date last_game
from us group by 1 order by 2 desc;

-- 2. US leagues by calendar year of the game.
select league, extract(year from game_start_time)::int game_year, count(*) games, round(100.0*avg((w = 1)::int), 1) home_win_pct
from us group by 1, 2 having count(*) >= 100 order by 1, 2;

-- Soccer: the three result markets of a match, home named first in the draw market.
create temp table soccer_draw as
select m.event_slug, split_part(m.event_slug, '-', 1) league, mo.winning_outcome w, m.game_start_time,
       coalesce(substring(m.title from '^Will (.*) vs\. .* end in a draw\?$'), substring(m.group_item_title from '^Draw \((.*) vs\. .*\)$')) home,
       coalesce(substring(m.title from '^Will .* vs\. (.*) end in a draw\?$'), substring(m.group_item_title from '^Draw \(.* vs\. (.*)\)$')) away
from markets m join market_outcomes mo on mo.condition_id = m.condition_id
where m.category = 'Soccer' and m.sports_market_type = 'moneyline' and m.outcome_yes = 'Yes'
  and (m.group_item_title like 'Draw (%' or m.title like '%end in a draw%') and mo.winning_outcome in (0, 1)
  and m.game_start_time < timestamptz '2026-09-14';
create temp table soccer_team as
select m.event_slug, m.group_item_title team, m.condition_id, mo.winning_outcome w, mo.resolved_at
from markets m join market_outcomes mo on mo.condition_id = m.condition_id
where m.category = 'Soccer' and m.sports_market_type = 'moneyline' and m.outcome_yes = 'Yes'
  and m.title like 'Will % win on %' and m.group_item_title not like 'Draw (%' and mo.winning_outcome in (0, 1);
create temp table soccer as
select d.event_slug, d.league, d.game_start_time, d.w draw_w, h.w home_w, a.w away_w, h.condition_id home_cid, a.condition_id away_cid
from soccer_draw d
join soccer_team h on h.event_slug = d.event_slug and h.team = d.home
join soccer_team a on a.event_slug = d.event_slug and a.team = d.away
where d.home is not null and d.away is not null;

-- Soccer universe: club league and cup matches. Left out, by the Gamma series title of each slug prefix
-- (soccer-prefix-series.tsv): national-team competitions (fifwc FIFA World Cup, fif FIFA
-- Friendly, icwq, u20wwc, uef, unl, wwcquefa, asean, afc, caf, cof, con), club friendlies (clf), and one-match
-- super cups usually played at a neutral venue (ecs, frtc, gsc, ptsc, ssc, trsk, usc).
create temp table soccer_club as select * from soccer where league not in ('fifwc', 'fif', 'icwq', 'u20wwc', 'uef', 'unl', 'wwcquefa', 'asean', 'afc', 'caf', 'cof', 'con', 'clf', 'ecs', 'frtc', 'gsc', 'ptsc', 'ssc', 'trsk', 'usc');

-- 3. Soccer: complete matches, the one-Yes check, and home, draw and away rates overall.
select count(*) matches, count(*) filter (where (draw_w = 0)::int + (home_w = 0)::int + (away_w = 0)::int = 1) exactly_one_yes,
       round(100.0*avg((home_w = 0)::int), 1) home_win_pct, round(100.0*avg((draw_w = 0)::int), 1) draw_pct, round(100.0*avg((away_w = 0)::int), 1) away_win_pct,
       round(100*1.959964*sqrt(avg((home_w = 0)::int)::numeric*(1-avg((home_w = 0)::int)::numeric)/count(*)), 2) home_half_width_pts,
       min(game_start_time)::date first_match, max(game_start_time)::date last_match
from soccer_club;

-- 4. Soccer by competition, 200 or more complete matches, with the latest fixture as evidence of the name.
select s.league, count(*) matches, round(100.0*avg((home_w = 0)::int), 1) home_win_pct, round(100.0*avg((draw_w = 0)::int), 1) draw_pct,
       round(100.0*avg((away_w = 0)::int), 1) away_win_pct,
       round(100*1.959964*sqrt(avg((home_w = 0)::int)::numeric*(1-avg((home_w = 0)::int)::numeric)/count(*)), 2) home_half_width_pts,
       (array_agg(d.home || ' vs. ' || d.away order by s.game_start_time desc))[1] latest_fixture
from soccer_club s join soccer_draw d using (event_slug)
group by 1 having count(*) >= 200 order by 2 desc;

-- 5. Large buys from April 2, 2026: US moneylines by side (outcome 1 is the home team) and soccer team-to-win Yes
--    buys by side, club competitions only. Price band: under 50 cents is the side priced as the underdog.
create temp table hb as
select w.id, w.condition_id, w.traded_at, w.price_num, w.usdc_notional_num, u.league,
       case when w.outcome_index = 1 then 'Home' else 'Away' end side,
       (w.outcome_index = u.w)::int won, (w.traded_at >= u.game_start_time) in_play
from whale_alerts w join us u on u.condition_id = w.condition_id
where w.platform = 'polymarket' and w.side = 0 and w.traded_at >= date '2026-04-02' and w.traded_at < date '2026-09-14'
  and u.resolved_at > w.traded_at and w.price_num between 0.02 and 0.98 and w.outcome_index in (0, 1)
union all
select w.id, w.condition_id, w.traded_at, w.price_num, w.usdc_notional_num, 'soccer',
       case when w.condition_id = s.home_cid then 'Home' else 'Away' end,
       (w.outcome_index = t.w)::int, (w.traded_at >= s.game_start_time)
from whale_alerts w
join soccer_club s on w.condition_id in (s.home_cid, s.away_cid)
join soccer_team t on t.condition_id = w.condition_id
where w.platform = 'polymarket' and w.side = 0 and w.outcome_index = 0 and w.traded_at >= date '2026-04-02' and w.traded_at < date '2026-09-14'
  and t.resolved_at > w.traded_at and w.price_num between 0.02 and 0.98;
select count(*) buys, count(distinct condition_id) markets, round(sum(usdc_notional_num)/1e6, 1) notional_musd,
       round(100.0*avg(in_play::int), 1) in_play_pct, min(traded_at)::date first_buy, max(traded_at)::date last_buy from hb;
select league, side, count(*) buys, count(distinct condition_id) markets, round(sum(usdc_notional_num)/1e6, 1) notional_musd,
       round(avg(price_num)*100, 1) avg_price_c, round(avg(won)::numeric*100, 1) win_pct,
       round((avg(won)::numeric - avg(price_num))*100, 2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num - 1))/sum(usdc_notional_num))*100, 2) dollar_roi_pct
from hb group by rollup(1, 2) order by 1, 2;

-- 6. By side and whether the side was priced as the favorite (50 cents and up) or the underdog.
select side, case when price_num < 0.5 then 'underdog' else 'favorite' end priced_as, count(*) buys, count(distinct condition_id) markets,
       round(avg(price_num)*100, 1) avg_price_c, round(avg(won)::numeric*100, 1) win_pct, round((avg(won)::numeric - avg(price_num))*100, 2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num - 1))/sum(usdc_notional_num))*100, 2) dollar_roi_pct
from hb group by 1, 2 order by 1, 2;

-- 7. Market-level export for the clustered bootstrap: league and side, all by side, side and price band.
\copy (select grp, condition_id, count(*) n, sum(won::numeric - price_num) sum_edge from (select league || ' | ' || side as grp, condition_id, won, price_num from hb union all select 'All leagues | ' || side, condition_id, won, price_num from hb union all select side || ' priced as ' || case when price_num < 0.5 then 'underdog' else 'favorite' end, condition_id, won, price_num from hb) x group by 1, 2) to './home-advantage-market-edge.csv' with (format csv, header true)
