-- #23664 (epic #23652, slice R1): section charts for /research/favorite-longshot-bias-polymarket-sports.
-- Read-only. Run through scripts/prod-read.sh against the production READ REPLICA: one statement per call, inside
-- BEGIN READ ONLY with statement_timeout 60s, results through a capped cursor. Output: the -output.txt beside this file.
-- The article's other charts read the 2026-10-10 run (calibration-2026-10-10.sql, queries 7, 9 and 10).
-- The taker-fee chart reads Polymarket's published fee schedule; the output file quotes it with its URL and read time.

-- A. The outcome_index defect that sets the study window (#13182): sports buys at 80c to 98c from February to May
-- 2026, on markets that settled yes or no after the trade, by month and by the outcome_index the alert table stored.
-- A favorite at 88c should win about 88% of the time whichever outcome it is.
select to_char(date_trunc('month', w.traded_at), 'YYYY-MM') mo, w.outcome_index,
       count(*) n,
       round(avg((w.outcome_index = o.winning_outcome)::int) * 100, 1) won_pct,
       round(avg(w.price_num) * 100, 1) avg_price_c
from whale_alerts w
join market_outcomes o on o.condition_id = w.condition_id
where w.platform = 'polymarket' and w.side = 0
  and w.traded_at >= date '2026-02-01' and w.traded_at < date '2026-06-01'
  and w.category in ('Soccer','NBA','Esports','Tennis','Baseball','Hockey','Basketball','Cricket',
                     'MMA','NFL','Golf','WNBA','Formula 1','Boxing','NCAAF','NCAAB','Table Tennis',
                     'NBA Summer League','CFL','Sports','Big Game','Pickleball')
  and o.winning_outcome in (0, 1) and o.resolved_at > w.traded_at
  and w.price_num between 0.80 and 0.98
group by 1, 2 order by 1, 2;
