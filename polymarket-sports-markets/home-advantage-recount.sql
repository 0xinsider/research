-- Home advantage recount (#13887): the game and per-buy exports behind the corrected study. Read-only, a read-only
-- role against production.  psql "$DATABASE_URL" -X -f home-advantage-recount.sql
-- The game and buy definitions are the #13781 study's, unchanged (home-advantage.sql): one
-- settled full-game moneyline per US league event, club soccer matches with all three result markets settled, and
-- every large-trade alert buy on those markets from April 2, 2026, settled after the trade, 2 to 98 cents. What
-- changes is who is at home: home-espn-check.py matches every game to ESPN's schedule, and the
-- recount and pricing scripts read ESPN's home team, so the buy export keeps Polymarket's outcome index.
select now() as run_at;

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
-- (2026-09-13-sports-soccer-prefix-series.tsv): national-team competitions (fifwc FIFA World Cup, fif FIFA
-- Friendly, icwq, u20wwc, uef, unl, wwcquefa, asean, afc, caf, cof, con), club friendlies (clf), and one-match
-- super cups usually played at a neutral venue (ecs, frtc, gsc, ptsc, ssc, trsk, usc).
create temp table soccer_club as select * from soccer where league not in ('fifwc', 'fif', 'icwq', 'u20wwc', 'uef', 'unl', 'wwcquefa', 'asean', 'afc', 'caf', 'cof', 'con', 'clf', 'ecs', 'frtc', 'gsc', 'ptsc', 'ssc', 'trsk', 'usc');

create temp table hb as
select w.id, w.condition_id, w.traded_at, w.price_num, w.usdc_notional_num, u.league,
       w.outcome_index, case when w.outcome_index = 1 then 'Home' else 'Away' end side,
       (w.outcome_index = u.w)::int won, (w.traded_at >= u.game_start_time) in_play
from whale_alerts w join us u on u.condition_id = w.condition_id
where w.platform = 'polymarket' and w.side = 0 and w.traded_at >= date '2026-04-02' and w.traded_at < date '2026-09-14'
  and u.resolved_at > w.traded_at and w.price_num between 0.02 and 0.98 and w.outcome_index in (0, 1)
union all
select w.id, w.condition_id, w.traded_at, w.price_num, w.usdc_notional_num, 'soccer',
       w.outcome_index, case when w.condition_id = s.home_cid then 'Home' else 'Away' end,
       (w.outcome_index = t.w)::int, (w.traded_at >= s.game_start_time)
from whale_alerts w
join soccer_club s on w.condition_id in (s.home_cid, s.away_cid)
join soccer_team t on t.condition_id = w.condition_id
where w.platform = 'polymarket' and w.side = 0 and w.outcome_index = 0 and w.traded_at >= date '2026-04-02' and w.traded_at < date '2026-09-14'
  and t.resolved_at > w.traded_at and w.price_num between 0.02 and 0.98;

-- 1. The game export: one row per US league game, the first outcome as `away`, as the #13781 study read it.
select league, count(*) games from us group by 1 order by 1;
\copy (select condition_id, event_slug, league, away, home, to_char(game_start_time at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') game_start_utc, w winning_outcome from us order by league, game_start_time, event_slug) to 'home-advantage-games.csv' with csv header

-- 2. The buy export's size, to tie it to the #13781 run (104,703 buys on 2026-09-13).
select count(*) buys, count(distinct condition_id) markets, round(sum(usdc_notional_num)/1e6, 1) notional_musd from hb;

-- 3. Per-buy export: league, market, Polymarket outcome index, the side the #13781 reading gave it, price, stake,
--    result and whether the buy landed after the start.
\copy (select id, league, condition_id, outcome_index, side as title_side, price_num, usdc_notional_num, won, in_play::int in_play from hb order by id) to 'home-advantage-buys.csv' with csv header
