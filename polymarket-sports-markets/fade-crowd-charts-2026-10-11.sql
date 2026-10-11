-- #23664 (epic #23652, slice R1): section charts for /research/fading-the-crowd-polymarket-sports.
-- Read-only. Run through scripts/prod-read.sh against the production READ REPLICA: one statement per call, inside
-- BEGIN READ ONLY with statement_timeout 60s, results through a capped cursor. Output: the -output.txt beside this file.
-- The article's other charts read the 2026-10-07 run (grade-at-trade-2026-10-07.sql, section 4).

-- D. The pattern a reader can see now: pre-kickoff sports buys from 2026-09-21 to 2026-10-10 (UTC days), graded by
-- the grade the wallet showed at the fill (grade_forward_at; the at-fill history covers every wallet from
-- 2026-09-20). Settled or not: this counts what the boards and the feed showed, not what won. Same construction as
-- the study: per market, each cohort's dollars by side; a market enters a cohort's bands with $5,000 or more of that
-- cohort's money across two or more buys; the lean is the heavier side's share. Plus every market with a
-- pre-kickoff buy. A game is the market's event slug with the "-more-markets" suffix removed.
with b as (
  select w.trader_id, w.condition_id, w.outcome_index, w.price_num p, w.usdc_notional_num usd,
         coalesce(regexp_replace(m.event_slug, '-more-markets$', ''), w.condition_id) ev,
         case when g.known and g.grade in ('S','A','B') then 'sab'
              when g.known and g.grade in ('D','F') then 'df' else 'other' end cohort
  from whale_alerts w
  join markets m on m.condition_id = w.condition_id
  cross join lateral grade_forward_at(w.trader_id, w.traded_at) g
  where w.platform = 'polymarket' and w.side = 0
    and w.traded_at >= timestamptz '2026-09-21 00:00:00+00' and w.traded_at < timestamptz '2026-10-11 00:00:00+00'
    and w.category in ('Soccer','NBA','Esports','Tennis','Baseball','Hockey','Basketball','Cricket',
                       'MMA','NFL','Golf','WNBA','Formula 1','Boxing','NCAAF','NCAAB','Table Tennis',
                       'NBA Summer League','CFL','Sports','Big Game','Pickleball')
    and (m.sports_market_type in ('moneyline','child_moneyline','spreads','totals') or m.sports_market_type is null)
    and m.game_start_time is not null and w.traded_at < m.game_start_time
    and w.price_num between 0.02 and 0.98),
mk as (
  select condition_id, max(ev) ev,
         sum(usd) filter (where cohort = 'df' and outcome_index = 0) df0, sum(usd) filter (where cohort = 'df' and outcome_index = 1) df1,
         sum(usd) filter (where cohort = 'sab' and outcome_index = 0) sab0, sum(usd) filter (where cohort = 'sab' and outcome_index = 1) sab1,
         count(*) filter (where cohort = 'df') n_df, count(*) filter (where cohort = 'sab') n_sab,
         count(distinct trader_id) filter (where cohort = 'df') w_df, count(distinct trader_id) filter (where cohort = 'sab') w_sab
  from b group by 1),
lean as (
  select 'df' cohort, ev, w_df wallets,
         greatest(coalesce(df0,0), coalesce(df1,0)) / (coalesce(df0,0) + coalesce(df1,0)) lean
  from mk where coalesce(df0,0) + coalesce(df1,0) >= 5000 and n_df >= 2
  union all
  select 'sab', ev, w_sab,
         greatest(coalesce(sab0,0), coalesce(sab1,0)) / (coalesce(sab0,0) + coalesce(sab1,0))
  from mk where coalesce(sab0,0) + coalesce(sab1,0) >= 5000 and n_sab >= 2)
select cohort, case when lean >= 0.9 then 'a90' when lean >= 0.7 then 'b70' else 'c' end band,
       count(*) markets, count(distinct ev) games, round(avg(wallets), 1) avg_wallets
from lean group by 1, 2
union all
select 'all', 'markets with a pre-kickoff buy', count(*), count(distinct ev), null from mk
order by 1, 2;
