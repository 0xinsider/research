-- 0xinsider/0xinsider#23716 -- the stake floor of the sports studies' large-trade samples, by month.
--
-- Read-only against the production READ REPLICA through ./scripts/prod-read.sh (every statement runs inside
-- BEGIN READ ONLY ... ROLLBACK with a 60 s statement timeout, results through a capped cursor) on 2026-10-11.
-- No row was written. Each query below is the file the run read, followed by its output verbatim (psql's
-- BEGIN/SET/ROLLBACK tags and the script's stderr lines removed). The run-time reads bracket the run; the
-- statements ran once each, in the order B, C, D, F, E, A, F2 (a run-time read at 14:14:42.525271 UTC fell
-- between A and F2). A second run, 14:29:53 to 14:40:01 UTC, read G, H1, H2 and I in that order; three earlier
-- forms of H passed the 60 s timeout and returned nothing (the H1 and H2 headers say why).
--
-- Why. These studies described their sample as buys "of $1,000 or more". None of their queries filters on
-- stake: the sample is whatever whale_alerts recorded. Each query here re-reads one study's own universe (same
-- table, filters and window as its committed query, named in its header) and returns, per trade month (UTC),
-- the buys, the smallest stake, the buys under $3,000 and under $10,000, and the last buy under $10,000.
--
-- Finding. In all ten universes (A to I; F2 is a later window) the smallest buy is $2,996; every month from April (June for the two graded
-- studies) through July has a smallest buy of $2,996 to $3,000, except H2's July, whose 120 club-soccer buys are
-- all $10,000 or more; the last buy under $10,000 landed on 2026-07-02 (13:12:20 UTC at the latest; H2's on
-- 2026-06-28); August and September have no buy under $10,000. F2 shows the same $10,000 floor
-- on the fading study's recent window (2026-09-21 to 2026-10-10). The all-category minimum near $1,000 (query 10
-- of calibration-2026-10-10.sql) is not the floor of any sports sample.
--
-- Universe counts against the published runs (markets settled since each run add buys; the floor is the finding):
--   A favorite-longshot-bias-polymarket-sports  416,882 here, 416,548 published (2026-10-10 run)
--   B both-teams-to-score-polymarket              3,684 here,   3,591 published (2026-09-13 run)
--   C point-spreads-polymarket                   31,066 here,  30,158 published (2026-09-13 run)
--   D soccer-draws-polymarket                    92,784 here,  92,313 published (2026-09-13 run)
--   E sharp-money-polymarket-sports             161,464 here, 161,128 published (2026-10-07 run)
--   F fading-the-crowd-polymarket-sports         74,419 here,  74,189 published (2026-10-07 run)
--   G over-under-polymarket-sports               47,121 here,  47,121 published (2026-10-10 run)
--   H home-field-advantage-polymarket           106,233 here (H1 84,011 + H2 22,222), 104,445 published
--     (2026-09-14 run, after one moneyline per US event and the ESPN game filter; H1 widens both, see its header)
--   I quoted spread, timing-2026-10-10.sql query 8 (charted by line-movement-sports-betting-explained and
--     how-to-tell-if-a-polymarket-price-is-fair)  229,679 here, 229,426 published (2026-10-10 run)
-- when-large-sports-bets-land's own universe was read by month in timing-charts-2026-10-11.sql
-- (queries 1 and 2, 13:22 UTC) with the same result; it is not repeated here.
--
-- Each statement below ran alone; its output, with the statement above it, is in large-trade-floor-2026-10-11-output.txt.

-- ===== run time =====
select now() as run_at_utc;

-- ===== A-favorite-longshot-bias =====
-- A. favorite-longshot-bias-polymarket-sports. The universe of calibration-2026-10-10.sql (view sports_buys):
-- Polymarket buys in whale_alerts on the 22 sports categories, traded 2026-04-02 to before 2026-09-12, on a market
-- settled 0 or 1 after the trade, 2c to 98c. The study's left join to markets is dropped: markets.condition_id is its
-- primary key, so the join adds no row and removes none. By month (UTC), then the total.
select to_char(w.traded_at at time zone 'UTC', 'YYYY-MM') trade_month,
       count(*) buys,
       round(min(w.usdc_notional_num)) min_stake_usd,
       count(*) filter (where w.usdc_notional_num < 3000) under_3k,
       count(*) filter (where w.usdc_notional_num < 10000) under_10k,
       max(w.traded_at) filter (where w.usdc_notional_num < 10000) last_under_10k
from whale_alerts w
join market_outcomes mo on mo.condition_id = w.condition_id
where w.platform = 'polymarket' and w.side = 0
  and w.traded_at >= date '2026-04-02' and w.traded_at < date '2026-09-12'
  and w.category in ('Soccer','NBA','Esports','Tennis','Baseball','Hockey','Basketball','Cricket',
                     'MMA','NFL','Golf','WNBA','Formula 1','Boxing','NCAAF','NCAAB','Table Tennis',
                     'NBA Summer League','CFL','Sports','Big Game','Pickleball')
  and mo.winning_outcome in (0, 1) and mo.resolved_at > w.traded_at
  and w.price_num between 0.02 and 0.98
group by rollup(1) order by 1;

-- ===== B-both-teams-to-score =====
-- B. both-teams-to-score-polymarket. Query 9's universe in btts-halftime.sql (temp table bb):
-- Polymarket buys in whale_alerts on settled both-teams-to-score markets (kickoff before 2026-09-14, settled 0 or 1),
-- traded 2026-04-02 to before 2026-09-14, settled after the trade, 2c to 98c. By month (UTC), then the total.
with btts as (
  select m.condition_id
  from markets m join market_outcomes mo on mo.condition_id = m.condition_id
  where m.sports_market_type = 'both_teams_to_score' and m.outcome_yes = 'Yes' and m.outcome_no = 'No'
    and m.game_start_time is not null and m.game_start_time < timestamptz '2026-09-14' and mo.winning_outcome in (0, 1)
)
select to_char(w.traded_at at time zone 'UTC', 'YYYY-MM') trade_month,
       count(*) buys,
       round(min(w.usdc_notional_num)) min_stake_usd,
       count(*) filter (where w.usdc_notional_num < 3000) under_3k,
       count(*) filter (where w.usdc_notional_num < 10000) under_10k,
       max(w.traded_at) filter (where w.usdc_notional_num < 10000) last_under_10k
from whale_alerts w
join btts b on b.condition_id = w.condition_id
join market_outcomes mo on mo.condition_id = w.condition_id
where w.platform = 'polymarket' and w.side = 0
  and w.traded_at >= date '2026-04-02' and w.traded_at < date '2026-09-14'
  and mo.resolved_at > w.traded_at and w.price_num between 0.02 and 0.98
group by rollup(1) order by 1;

-- ===== C-point-spreads =====
-- C. point-spreads-polymarket. Query 6's universe in spreads.sql (temp tables sp and bb):
-- Polymarket buys in whale_alerts on settled spread markets titled "Spread: <team> (-X.5)" (kickoff before 2026-09-14,
-- settled 0 or 1, the eight categories), traded 2026-04-02 to before 2026-09-14, settled after the trade, 2c to 98c,
-- outcome 0 or 1. By month (UTC), then the total.
with sp as (
  select m.condition_id, mo.resolved_at
  from markets m join market_outcomes mo on mo.condition_id = m.condition_id
  where m.sports_market_type = 'spreads' and mo.winning_outcome in (0, 1) and m.game_start_time < timestamptz '2026-09-14'
    and m.category in ('NFL', 'NCAAF', 'NBA', 'Basketball', 'WNBA', 'Baseball', 'Hockey', 'Soccer')
    and m.title ~ '^Spread: .* \(-[0-9.]+\)$' and substring(m.title from '^Spread: (.*) \(-[0-9.]+\)$') = m.outcome_yes
)
select to_char(w.traded_at at time zone 'UTC', 'YYYY-MM') trade_month,
       count(*) buys,
       round(min(w.usdc_notional_num)) min_stake_usd,
       count(*) filter (where w.usdc_notional_num < 3000) under_3k,
       count(*) filter (where w.usdc_notional_num < 10000) under_10k,
       max(w.traded_at) filter (where w.usdc_notional_num < 10000) last_under_10k
from whale_alerts w
join sp s on s.condition_id = w.condition_id
where w.platform = 'polymarket' and w.side = 0
  and w.traded_at >= date '2026-04-02' and w.traded_at < date '2026-09-14'
  and s.resolved_at > w.traded_at and w.price_num between 0.02 and 0.98 and w.outcome_index in (0, 1)
group by rollup(1) order by 1;

-- ===== D-soccer-draws =====
-- D. soccer-draws-polymarket. Query 4's universe in soccer-draws.sql (views legs and buys):
-- Polymarket buys in whale_alerts (category Soccer) on settled soccer moneyline legs with outcomes Yes/No (kickoff
-- 2026-04-02 to before 2026-09-14, settled 0 or 1), traded 2026-04-02 to before 2026-09-14, settled after the trade,
-- 2c to 98c. By month (UTC), then the total. The grade split (grade-at-trade-2026-10-07.sql, cut dr) is the
-- June-to-September part of the same universe.
with legs as (
  select m.condition_id
  from markets m join market_outcomes mo on mo.condition_id = m.condition_id
  where m.category = 'Soccer' and m.sports_market_type = 'moneyline' and m.outcome_yes = 'Yes' and m.outcome_no = 'No'
    and m.game_start_time >= timestamptz '2026-04-02' and m.game_start_time < timestamptz '2026-09-14'
    and mo.winning_outcome in (0, 1)
)
select to_char(w.traded_at at time zone 'UTC', 'YYYY-MM') trade_month,
       count(*) buys,
       round(min(w.usdc_notional_num)) min_stake_usd,
       count(*) filter (where w.usdc_notional_num < 3000) under_3k,
       count(*) filter (where w.usdc_notional_num < 10000) under_10k,
       max(w.traded_at) filter (where w.usdc_notional_num < 10000) last_under_10k
from whale_alerts w
join legs l on l.condition_id = w.condition_id
join market_outcomes mo on mo.condition_id = w.condition_id
where w.platform = 'polymarket' and w.side = 0 and w.category = 'Soccer'
  and w.traded_at >= date '2026-04-02' and w.traded_at < date '2026-09-14'
  and mo.resolved_at > w.traded_at and w.price_num between 0.02 and 0.98
group by rollup(1) order by 1;

-- ===== E-sharp-money =====
-- E. sharp-money-polymarket-sports. The sharp cut's universe in grade-at-trade-2026-10-07.sql (tables s22191,
-- ga attr pit, obs cut sharp): Polymarket buys in whale_alerts on the 22 sports categories, traded 2026-06-01 to
-- before 2026-09-12, on a market settled 0 or 1 after the trade, 2c to 98c. The study's left join to markets is
-- dropped: markets.condition_id is its primary key, so the join adds no row and removes none. By month (UTC), then
-- the total.
select to_char(w.traded_at at time zone 'UTC', 'YYYY-MM') trade_month,
       count(*) buys,
       round(min(w.usdc_notional_num)) min_stake_usd,
       count(*) filter (where w.usdc_notional_num < 3000) under_3k,
       count(*) filter (where w.usdc_notional_num < 10000) under_10k,
       max(w.traded_at) filter (where w.usdc_notional_num < 10000) last_under_10k
from whale_alerts w
join market_outcomes mo on mo.condition_id = w.condition_id
where w.platform = 'polymarket' and w.side = 0
  and w.traded_at >= timestamptz '2026-06-01' and w.traded_at < timestamptz '2026-09-12'
  and w.category in ('Soccer','NBA','Esports','Tennis','Baseball','Hockey','Basketball','Cricket',
                     'MMA','NFL','Golf','WNBA','Formula 1','Boxing','NCAAF','NCAAB','Table Tennis',
                     'NBA Summer League','CFL','Sports','Big Game','Pickleball')
  and mo.winning_outcome in (0, 1) and mo.resolved_at > w.traded_at
  and w.price_num between 0.02 and 0.98
group by rollup(1) order by 1;

-- ===== F-fading-the-crowd =====
-- F. fading-the-crowd-polymarket-sports. Section 4's universe in grade-at-trade-2026-10-07.sql (table fb, attr pit):
-- Polymarket buys in whale_alerts on the 22 sports categories, traded 2026-06-01 to before 2026-09-13, on a market
-- settled 0 or 1 after the trade, 2c to 98c, typed moneyline, child moneyline, spreads or totals (or untyped), with a
-- kickoff time, placed before kickoff. By month (UTC), then the total.
select to_char(w.traded_at at time zone 'UTC', 'YYYY-MM') trade_month,
       count(*) buys,
       round(min(w.usdc_notional_num)) min_stake_usd,
       count(*) filter (where w.usdc_notional_num < 3000) under_3k,
       count(*) filter (where w.usdc_notional_num < 10000) under_10k,
       max(w.traded_at) filter (where w.usdc_notional_num < 10000) last_under_10k
from whale_alerts w
join market_outcomes mo on mo.condition_id = w.condition_id
join markets m on m.condition_id = w.condition_id
where w.platform = 'polymarket' and w.side = 0
  and w.traded_at >= timestamptz '2026-06-01' and w.traded_at < timestamptz '2026-09-13'
  and w.category in ('Soccer','NBA','Esports','Tennis','Baseball','Hockey','Basketball','Cricket',
                     'MMA','NFL','Golf','WNBA','Formula 1','Boxing','NCAAF','NCAAB','Table Tennis',
                     'NBA Summer League','CFL','Sports','Big Game','Pickleball')
  and mo.winning_outcome in (0, 1) and mo.resolved_at > w.traded_at
  and w.price_num between 0.02 and 0.98
  and (m.sports_market_type in ('moneyline','child_moneyline','spreads','totals') or m.sports_market_type is null)
  and m.game_start_time is not null and w.traded_at < m.game_start_time
group by rollup(1) order by 1;

-- ===== F2-fading-the-crowd-recent-window =====
-- F2. fading-the-crowd-polymarket-sports, the recent-window chart. Query D's universe in
-- fade-crowd-charts-2026-10-11.sql (CTE b), without the grade lookup, which does not
-- filter rows: Polymarket buys in whale_alerts on the 22 sports categories from 2026-09-21 to before 2026-10-11 (UTC),
-- typed moneyline, child moneyline, spreads or totals (or untyped), with a kickoff time, placed before kickoff,
-- 2c to 98c, settled or not. One row.
select count(*) buys,
       round(min(w.usdc_notional_num)) min_stake_usd,
       count(*) filter (where w.usdc_notional_num < 10000) under_10k
from whale_alerts w
join markets m on m.condition_id = w.condition_id
where w.platform = 'polymarket' and w.side = 0
  and w.traded_at >= timestamptz '2026-09-21 00:00:00+00' and w.traded_at < timestamptz '2026-10-11 00:00:00+00'
  and w.category in ('Soccer','NBA','Esports','Tennis','Baseball','Hockey','Basketball','Cricket',
                     'MMA','NFL','Golf','WNBA','Formula 1','Boxing','NCAAF','NCAAB','Table Tennis',
                     'NBA Summer League','CFL','Sports','Big Game','Pickleball')
  and (m.sports_market_type in ('moneyline','child_moneyline','spreads','totals') or m.sports_market_type is null)
  and m.game_start_time is not null and w.traded_at < m.game_start_time
  and w.price_num between 0.02 and 0.98;

-- ===== run end =====
select now() as run_at_utc;

-- ===== second run =====
-- G, H1, H2 and I, read for the over-under study, the home-field study and the two learn guides that chart
-- the quoted spread. when-large-sports-bets-land's own floor was read in its chart run
-- (timing-charts-2026-10-11.sql, queries 1 and 2) and is not repeated here.

-- ===== second run time =====
select now() as run_at_utc;

-- ===== G-over-under =====
-- G. over-under-polymarket-sports. The universe of over-under-2026-10-10.sql (view tot): Polymarket buys in
-- whale_alerts on the 22 sports categories, on game-total markets (sports_market_type 'totals', outcomes Over/Under),
-- traded 2026-04-02 to before 2026-09-14, on a market settled 0 or 1 after the trade, 2c to 98c. By month (UTC), then
-- the total.
select to_char(w.traded_at at time zone 'UTC', 'YYYY-MM') trade_month,
       count(*) buys,
       round(min(w.usdc_notional_num)) min_stake_usd,
       count(*) filter (where w.usdc_notional_num < 3000) under_3k,
       count(*) filter (where w.usdc_notional_num < 10000) under_10k,
       max(w.traded_at) filter (where w.usdc_notional_num < 10000) last_under_10k
from whale_alerts w
join market_outcomes mo on mo.condition_id = w.condition_id
join markets m on m.condition_id = w.condition_id
where w.platform = 'polymarket' and w.side = 0
  and w.traded_at >= date '2026-04-02' and w.traded_at < date '2026-09-14'
  and w.category in ('Soccer','NBA','Esports','Tennis','Baseball','Hockey','Basketball','Cricket',
                     'MMA','NFL','Golf','WNBA','Formula 1','Boxing','NCAAF','NCAAB','Table Tennis',
                     'NBA Summer League','CFL','Sports','Big Game','Pickleball')
  and m.sports_market_type = 'totals' and m.outcome_yes = 'Over' and m.outcome_no = 'Under'
  and mo.winning_outcome in (0, 1) and mo.resolved_at > w.traded_at
  and w.price_num between 0.02 and 0.98
group by rollup(1) order by 1;

-- ===== H1-home-field-advantage-us =====
-- H1. home-field-advantage-polymarket, US half. The first branch of table hb in
-- home-advantage-recount.sql: Polymarket buys in whale_alerts from 2026-04-02 to before
-- 2026-09-14, settled after the trade, 2c to 98c, outcome 0 or 1, on settled full-game moneylines of US league events
-- (nba, nfl, mlb, nhl, wnba, cfb; title "<away> vs. <home>", no All-Star or 4 Nations). Two widenings, each of which can
-- only add buys: the study kept one moneyline per event (DISTINCT ON event_slug ordered by markets.volume, a column
-- migration 4001 has since dropped), and its pricing script then dropped games ESPN does not list as a regular-season,
-- postseason or play-in game at a home venue. The one-statement version of H (both halves) timed out at 60 s, so the
-- halves run separately. By month (UTC), then the total.
with us as (
  select m.condition_id, mo.resolved_at
  from markets m join market_outcomes mo on mo.condition_id = m.condition_id
  where m.sports_market_type = 'moneyline' and split_part(m.event_slug, '-', 1) in ('nba', 'nfl', 'mlb', 'nhl', 'wnba', 'cfb')
    and mo.winning_outcome in (0, 1) and m.outcome_yes <> 'Yes' and m.game_start_time < timestamptz '2026-09-14'
    and m.title !~* '(all-star|4 nations)'
    and regexp_replace(m.title, '^[^:]+: ', '') ~ ('^' || regexp_replace(m.outcome_yes, '([.*+?^${}()|\[\]\\])', '\\\1', 'g')
        || ' vs\.? ' || regexp_replace(m.outcome_no, '([.*+?^${}()|\[\]\\])', '\\\1', 'g') || ' ?$')
)
select to_char(w.traded_at at time zone 'UTC', 'YYYY-MM') trade_month,
       count(*) buys,
       round(min(w.usdc_notional_num)) min_stake_usd,
       count(*) filter (where w.usdc_notional_num < 3000) under_3k,
       count(*) filter (where w.usdc_notional_num < 10000) under_10k,
       max(w.traded_at) filter (where w.usdc_notional_num < 10000) last_under_10k
from whale_alerts w join us u on u.condition_id = w.condition_id
where w.platform = 'polymarket' and w.side = 0 and w.traded_at >= date '2026-04-02' and w.traded_at < date '2026-09-14'
  and u.resolved_at > w.traded_at and w.price_num between 0.02 and 0.98 and w.outcome_index in (0, 1)
group by rollup(1) order by 1;

-- ===== H2-home-field-advantage-soccer =====
-- H2. home-field-advantage-polymarket, soccer half. The second branch of table hb in
-- home-advantage-recount.sql: Polymarket buys of Yes (outcome 0) from 2026-04-02 to before
-- 2026-09-14, settled after the trade, 2c to 98c, on a team-to-win market of a club soccer match whose draw market and
-- both team markets settled 0 or 1 (draw kickoff before 2026-09-14; national-team competitions, club friendlies and
-- one-match super cups left out by slug prefix). The study's form (a sequential scan of markets for every soccer team
-- market, then w.condition_id IN (home_cid, away_cid)) passed the 60 s replica limit, so this form starts from the
-- buys: whale_alerts rows with category Soccer, then the same market, draw and other-team conditions per buy by
-- condition_id and event_slug. A buy counts once even if its event lists two draw markets.
-- By month (UTC), then the total.
select to_char(w.traded_at at time zone 'UTC', 'YYYY-MM') trade_month,
       count(*) buys,
       round(min(w.usdc_notional_num)) min_stake_usd,
       count(*) filter (where w.usdc_notional_num < 3000) under_3k,
       count(*) filter (where w.usdc_notional_num < 10000) under_10k,
       max(w.traded_at) filter (where w.usdc_notional_num < 10000) last_under_10k
from whale_alerts w
join markets m on m.condition_id = w.condition_id
join market_outcomes mo on mo.condition_id = w.condition_id
where w.platform = 'polymarket' and w.side = 0 and w.outcome_index = 0 and w.category = 'Soccer'
  and w.traded_at >= date '2026-04-02' and w.traded_at < date '2026-09-14'
  and mo.resolved_at > w.traded_at and w.price_num between 0.02 and 0.98
  and m.category = 'Soccer' and m.sports_market_type = 'moneyline' and m.outcome_yes = 'Yes'
  and m.title like 'Will % win on %' and m.group_item_title not like 'Draw (%' and mo.winning_outcome in (0, 1)
  and exists (
    select 1
    from markets d
    join market_outcomes dmo on dmo.condition_id = d.condition_id
    cross join lateral (
      select coalesce(substring(d.title from '^Will (.*) vs\. .* end in a draw\?$'), substring(d.group_item_title from '^Draw \((.*) vs\. .*\)$')) home,
             coalesce(substring(d.title from '^Will .* vs\. (.*) end in a draw\?$'), substring(d.group_item_title from '^Draw \(.* vs\. (.*)\)$')) away
    ) n
    where d.event_slug = m.event_slug and d.category = 'Soccer' and d.sports_market_type = 'moneyline' and d.outcome_yes = 'Yes'
      and (d.group_item_title like 'Draw (%' or d.title like '%end in a draw%') and dmo.winning_outcome in (0, 1)
      and d.game_start_time < timestamptz '2026-09-14'
      and split_part(d.event_slug, '-', 1) not in ('fifwc', 'fif', 'icwq', 'u20wwc', 'uef', 'unl', 'wwcquefa', 'asean', 'afc',
                                                   'caf', 'cof', 'con', 'clf', 'ecs', 'frtc', 'gsc', 'ptsc', 'ssc', 'trsk', 'usc')
      and n.home is not null and n.away is not null and m.group_item_title in (n.home, n.away)
      and exists (
        select 1
        from markets o
        join market_outcomes omo on omo.condition_id = o.condition_id
        where o.event_slug = m.event_slug and o.category = 'Soccer' and o.sports_market_type = 'moneyline' and o.outcome_yes = 'Yes'
          and o.title like 'Will % win on %' and o.group_item_title not like 'Draw (%' and omo.winning_outcome in (0, 1)
          and o.group_item_title = case when m.group_item_title = n.home then n.away else n.home end
      )
  )
group by rollup(1) order by 1;

-- ===== I-quoted-spread =====
-- I. line-movement-sports-betting-explained and how-to-tell-if-a-polymarket-price-is-fair (the quoted-spread chart).
-- Query 8 of timing-2026-10-10.sql: view sports_buys (Polymarket buys in whale_alerts on the 22 sports categories,
-- 2026-04-02 to before 2026-09-12, settled 0 or 1 after the trade, 2c to 98c, kickoff on record) with a stored book
-- quote (best_bid_num and best_ask_num not null, ask >= bid), traded before 2026-08-01. By month (UTC), then the total.
select to_char(w.traded_at at time zone 'UTC', 'YYYY-MM') trade_month,
       count(*) buys,
       round(min(w.usdc_notional_num)) min_stake_usd,
       count(*) filter (where w.usdc_notional_num < 3000) under_3k,
       count(*) filter (where w.usdc_notional_num < 10000) under_10k,
       max(w.traded_at) filter (where w.usdc_notional_num < 10000) last_under_10k
from whale_alerts w
join market_outcomes mo on mo.condition_id = w.condition_id
join markets m on m.condition_id = w.condition_id
where w.platform = 'polymarket' and w.side = 0
  and w.traded_at >= date '2026-04-02' and w.traded_at < date '2026-08-01'
  and w.category in ('Soccer','NBA','Esports','Tennis','Baseball','Hockey','Basketball','Cricket',
                     'MMA','NFL','Golf','WNBA','Formula 1','Boxing','NCAAF','NCAAB','Table Tennis',
                     'NBA Summer League','CFL','Sports','Big Game','Pickleball')
  and mo.winning_outcome in (0, 1) and mo.resolved_at > w.traded_at
  and w.price_num between 0.02 and 0.98
  and m.game_start_time is not null
  and w.best_bid_num is not null and w.best_ask_num is not null and w.best_ask_num >= w.best_bid_num
group by rollup(1) order by 1;

-- ===== second run end =====
select now() as run_at_utc;
