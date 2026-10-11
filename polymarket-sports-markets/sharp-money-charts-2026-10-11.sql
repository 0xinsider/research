-- #23664 (epic #23652, slice R1): section charts for /research/sharp-money-polymarket-sports.
-- Read-only. Run through scripts/prod-read.sh against the production READ REPLICA: one statement per call, inside
-- BEGIN READ ONLY with statement_timeout 60s, results through a capped cursor. Output: the -output.txt beside this file.
-- The article's other charts read the 2026-10-07 run (grade-at-trade-2026-10-07.sql).

-- B. Grade coverage: trader_rankings rows per day, and the rows that carry a grade, averaged over each calendar month.
-- Run once per month with __FROM__ / __TO__ replaced: 2026-04-01..2026-05-01, 2026-05-01..2026-06-01,
-- 2026-06-01..2026-07-01, 2026-07-01..2026-08-01, 2026-08-01..2026-09-01, 2026-10-01..2026-10-11.
-- September as one month passed the 60s timeout, so it runs as B2, day by day, in three ten-day calls.
with d as (
  select date, count(*) n, count(*) filter (where grade is not null) graded
  from trader_rankings
  where date >= date '__FROM__' and date < date '__TO__'
  group by date)
select to_char(date_trunc('month', min(date)), 'YYYY-MM') mo, count(*) days,
       round(avg(n)) avg_rows_per_day, round(avg(graded)) avg_graded_per_day,
       min(graded) min_graded_day, max(graded) max_graded_day
from d;

-- B2. The same counts for each day: __FROM__ / __TO__ = 2026-09-01..2026-09-11, 2026-09-11..2026-09-21,
-- 2026-09-21..2026-10-01.
select date, count(*) n, count(*) filter (where grade is not null) graded
from trader_rankings
where date >= date '__FROM__' and date < date '__TO__'
group by date order by date;

-- C. The large-trade feed: sports trades (buys and sells) from 2026-09-21 to 2026-10-10 (UTC days), by the grade
-- the wallet showed when the order filled (grade_forward_at). The window starts on 2026-09-21, the first full day
-- after the at-fill grade history covers every wallet (2026-09-20 04:46 UTC); a first run from 2026-09-11 is in the
-- output to show why.
with t as (
  select w.id, w.side, w.usdc_notional_num usd, g.grade, g.known
  from whale_alerts w
  cross join lateral grade_forward_at(w.trader_id, w.traded_at) g
  where w.platform = 'polymarket' and w.side in (0, 1)
    and w.traded_at >= timestamptz '2026-09-21 00:00:00+00' and w.traded_at < timestamptz '2026-10-11 00:00:00+00'
    and w.category in ('Soccer','NBA','Esports','Tennis','Baseball','Hockey','Basketball','Cricket',
                       'MMA','NFL','Golf','WNBA','Formula 1','Boxing','NCAAF','NCAAB','Table Tennis',
                       'NBA Summer League','CFL','Sports','Big Game','Pickleball'))
select case when not known then 'unknown history' when grade is null then 'no grade' else grade end grade_at_fill,
       count(*) trades, count(*) filter (where side = 0) buys,
       round(sum(usd) / 1e6, 2) musd
from t group by 1 order by 1;

-- E. Concentration of the S, A and B cohort: the study's universe (sports buys of $1,000 or more, 2026-06-01 to
-- 2026-09-11, 2c to 98c, on a yes-or-no market that settled after the trade), each buy graded by the latest ranking
-- row dated on or before the trade day AND last written at or before the trade, as in
-- grade-at-trade-2026-10-07.sql. One run over the whole window passed the 60s timeout, so it ran in four date
-- chunks (__FROM__ / __TO__ = 2026-06-01..2026-06-16, 2026-06-16..2026-07-01, 2026-07-01..2026-08-01,
-- 2026-08-01..2026-09-12) with --csv, one row per S, A or B wallet (a 12-character md5 prefix of its id).
-- The rows are sharp-money-charts-2026-10-11-concentration.csv; the .py beside it adds them up.
with b as (
  select w.trader_id, w.usdc_notional_num usd,
         (select tr.grade from trader_rankings tr
           where tr.trader_id = w.trader_id and tr.date <= w.traded_at::date and tr.computed_at <= w.traded_at
           order by tr.date desc limit 1) g
  from whale_alerts w
  join market_outcomes mo on mo.condition_id = w.condition_id
  left join markets m on m.condition_id = w.condition_id
  where w.platform = 'polymarket' and w.side = 0
    and w.traded_at >= '__FROM__' and w.traded_at < '__TO__'
    and (w.category in ('Soccer','NBA','Esports','Tennis','Baseball','Hockey','Basketball','Cricket',
                        'MMA','NFL','Golf','WNBA','Formula 1','Boxing','NCAAF','NCAAB','Table Tennis',
                        'NBA Summer League','CFL','Sports','Big Game','Pickleball')
         or m.category in ('NFL','NCAAF','NBA','Basketball','WNBA','Baseball','Hockey','Soccer'))
    and mo.winning_outcome in (0, 1) and mo.resolved_at > w.traded_at
    and w.price_num between 0.02 and 0.98)
select left(md5(trader_id::text), 12) wallet, count(*) n, round(sum(usd)) usd
from b where g in ('S','A','B') group by 1 order by 1;

-- F. The two most active wallets in E, by their md5 prefix.
select left(md5(id::text), 12) wallet, address, username
from traders where left(md5(id::text), 12) in ('6d316ffe7475', 'a7681a0edd3e');
