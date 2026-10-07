-- Grade vs price paid, Polymarket large buys. Corrected run, 2026-10-07.
--
-- Read-only, against the production read replica (0xinsider's scripts/prod-read.sh wraps each
-- statement in BEGIN READ ONLY ... ROLLBACK with a 60 s statement timeout). Every statement below
-- is the text that produced results.md. Nothing is written.
--
-- WHAT CHANGED FROM 2026-09-12 (2026-09-12-superseded/queries.sql).
-- 1. The grade. The September query took the latest trader_rankings row dated on or before the
--    trade day. 0xinsider updates a wallet's latest ranking row in place when it recomputes the
--    grade and sets computed_at = NOW(), so that row could carry a grade decided after the trade,
--    partly by the trades being scored (look-ahead). Query 2 measures it: 99.3% of the S, A and B
--    buys it scored used a row last written after the trade. Every query here takes the grade at
--    the trade instead:
--      - from 2026-09-20 04:46 UTC, when 0xinsider's grade history baseline completed, the grade
--        the wallet showed when the order filled (grade_forward_at, known = true);
--      - before that, the latest ranking row dated on or before the trade day AND last written at
--        or before the trade (tr.computed_at <= traded_at).
--    Never drop the computed_at bound: without it the query reintroduces the look-ahead.
-- 2. The universe. winning_outcome IN (0, 1). The September query used IS NOT NULL, which scored
--    318 buys on void (-1) or unresolved (-2) markets as losses.
-- 3. The intervals. 1.96 cluster-robust standard errors, clustered by market and, separately, by
--    wallet; the wider is reported. The September intervals were a market bootstrap.
--
-- Edge = share of buys whose side won minus average price paid, in percentage points.

-- 1. The published window (2026-06-01 .. 2026-09-11), graded at the trade (last ranking row
--    written before it), by grade, with both clusterings. This is the like-for-like correction.
WITH b AS MATERIALIZED (
  SELECT w.trader_id, w.condition_id, w.traded_at, w.price_num::float8 p,
         w.usdc_notional_num::float8 usd, (w.outcome_index = mo.winning_outcome)::int won
  FROM whale_alerts w JOIN market_outcomes mo ON mo.condition_id = w.condition_id
  WHERE w.platform = 'polymarket' AND w.side = 0
    AND w.traded_at >= '2026-06-01' AND w.traded_at < '2026-09-12'
    AND w.usdc_notional_num >= 10000 AND mo.winning_outcome IN (0, 1)
    AND mo.resolved_at > w.traded_at AND w.price_num BETWEEN 0.02 AND 0.98
), a AS MATERIALIZED (
  SELECT b.*, coalesce((SELECT tr.grade FROM trader_rankings tr
            WHERE tr.trader_id = b.trader_id AND tr.date <= b.traded_at::date AND tr.computed_at <= b.traded_at
            ORDER BY tr.date DESC LIMIT 1), 'none') g
  FROM b
), x AS MATERIALIZED (
  SELECT g bk, trader_id, condition_id, won, p, usd FROM a
  UNION ALL SELECT 'S/A', trader_id, condition_id, won, p, usd FROM a WHERE g IN ('S','A')
  UNION ALL SELECT 'S/A/B', trader_id, condition_id, won, p, usd FROM a WHERE g IN ('S','A','B')
  UNION ALL SELECT 'D/F', trader_id, condition_id, won, p, usd FROM a WHERE g IN ('D','F')
  UNION ALL SELECT 'all', trader_id, condition_id, won, p, usd FROM a
), t AS (
  SELECT bk, count(*) n, count(DISTINCT trader_id) wl, count(DISTINCT condition_id) mk, sum(usd) usd,
         avg(won) wr, avg(p) pr, sum(won - p) / count(*) e
  FROM x GROUP BY 1
), m AS (SELECT bk, condition_id, count(*) n, sum(won - p) s FROM x GROUP BY 1, 2),
w AS (SELECT bk, trader_id, count(*) n, sum(won - p) s FROM x GROUP BY 1, 2),
cm AS (SELECT m.bk, sqrt(count(*)::float8 / greatest(count(*) - 1, 1) * sum((m.s - t.e * m.n)^2)) / t.n v
       FROM m JOIN t USING (bk) GROUP BY m.bk, t.n),
cw AS (SELECT w.bk, sqrt(count(*)::float8 / greatest(count(*) - 1, 1) * sum((w.s - t.e * w.n)^2)) / t.n v
       FROM w JOIN t USING (bk) GROUP BY w.bk, t.n)
SELECT 'pit' attr, t.bk, t.n trades, t.wl wallets, t.mk markets, round((t.usd / 1e6)::numeric, 1) notional_musd,
       round(100 * t.wr::numeric, 2) won_pct, round(100 * t.pr::numeric, 2) price_pct,
       round(100 * t.e::numeric, 2) edge, round(100 * 1.96 * cm.v::numeric, 2) ci_mkt,
       round(100 * 1.96 * cw.v::numeric, 2) ci_wallet,
       round(100 * 1.96 * greatest(cm.v, cw.v)::numeric, 2) ci
FROM t JOIN cm USING (bk) JOIN cw USING (bk)
ORDER BY array_position(ARRAY['S','A','B','C','D','F','none','S/A','S/A/B','D/F','all'], t.bk);

-- 2. The look-ahead, measured: the September universe and lookup (study) beside the grade at
--    the trade (pit), with the share of each cohort's buys whose ranking row was last written
--    after the trade. Market-clustered half-width.
WITH b AS MATERIALIZED (
  SELECT w.id, w.trader_id, w.condition_id, w.traded_at, w.price_num::float8 p,
         (w.outcome_index = mo.winning_outcome)::int won
  FROM whale_alerts w JOIN market_outcomes mo ON mo.condition_id = w.condition_id
  WHERE w.platform='polymarket' AND w.side=0
    AND w.traded_at >= '2026-06-01' AND w.traded_at < '2026-09-12'
    AND w.usdc_notional_num >= 10000 AND mo.winning_outcome IS NOT NULL
    AND mo.resolved_at > w.traded_at AND w.price_num BETWEEN 0.02 AND 0.98
), a AS MATERIALIZED (
  SELECT b.*, s.grade sg, s.computed_at s_comp,
         (SELECT tr.grade FROM trader_rankings tr
          WHERE tr.trader_id=b.trader_id AND tr.date <= b.traded_at::date AND tr.computed_at <= b.traded_at
          ORDER BY tr.date DESC LIMIT 1) pg
  FROM b LEFT JOIN LATERAL (
    SELECT tr.grade, tr.computed_at FROM trader_rankings tr
    WHERE tr.trader_id=b.trader_id AND tr.date <= b.traded_at::date ORDER BY tr.date DESC LIMIT 1) s ON true
), c AS (
  SELECT 'study' attribution,
         CASE WHEN sg IN ('S','A','B') THEN 'S/A/B' WHEN sg='C' THEN 'C' WHEN sg IN ('D','F') THEN 'D/F' ELSE 'no grade' END cohort,
         condition_id, won, p, (s_comp > traded_at) rewritten FROM a
  UNION ALL
  SELECT 'pit',
         CASE WHEN pg IN ('S','A','B') THEN 'S/A/B' WHEN pg='C' THEN 'C' WHEN pg IN ('D','F') THEN 'D/F' ELSE 'no grade' END,
         condition_id, won, p, NULL FROM a
), m AS (
  SELECT attribution, cohort, condition_id, count(*) n, sum(won-p) s FROM c GROUP BY 1,2,3
), t AS (SELECT attribution, cohort, sum(s)/sum(n) e, count(*) mk,
               sqrt(count(*)::float8/(count(*)-1)*0) z FROM m GROUP BY 1,2)
SELECT t.attribution, t.cohort, sum(m.n) trades, t.mk markets, round(100*t.e::numeric,2) edge_pts,
       round(100*1.96*sqrt(count(*)::float8/(count(*)-1)*sum((m.s - t.e*m.n)^2))::numeric/sum(m.n),2) ci_half,
       (SELECT round(100*avg(rewritten::int)::numeric,1) FROM c WHERE c.attribution=t.attribution AND c.cohort=t.cohort) pct_row_rewritten_after_trade
FROM t JOIN m USING (attribution, cohort)
GROUP BY t.attribution, t.cohort, t.e, t.mk ORDER BY 1 DESC, 2;

-- 3. Who moved: cohort under the September lookup (study) against the cohort at the trade (pit),
--    the September universe. Market-clustered half-width.
WITH b AS MATERIALIZED (
  SELECT w.trader_id, w.condition_id, w.traded_at, w.price_num::float8 p,
         (w.outcome_index = mo.winning_outcome)::int won
  FROM whale_alerts w JOIN market_outcomes mo ON mo.condition_id = w.condition_id
  WHERE w.platform='polymarket' AND w.side=0
    AND w.traded_at >= '2026-06-01' AND w.traded_at < '2026-09-12'
    AND w.usdc_notional_num >= 10000 AND mo.winning_outcome IS NOT NULL
    AND mo.resolved_at > w.traded_at AND w.price_num BETWEEN 0.02 AND 0.98
), a AS MATERIALIZED (
  SELECT b.*,
         (SELECT tr.grade FROM trader_rankings tr WHERE tr.trader_id=b.trader_id AND tr.date <= b.traded_at::date
          ORDER BY tr.date DESC LIMIT 1) sg,
         (SELECT tr.grade FROM trader_rankings tr WHERE tr.trader_id=b.trader_id AND tr.date <= b.traded_at::date
            AND tr.computed_at <= b.traded_at ORDER BY tr.date DESC LIMIT 1) pg
  FROM b
), c AS (
  SELECT CASE WHEN sg IN ('S','A','B') THEN 'SAB' WHEN sg = 'C' THEN 'C' WHEN sg IN ('D','F') THEN 'DF' ELSE 'none' END sc,
         CASE WHEN pg IN ('S','A','B') THEN 'SAB' WHEN pg = 'C' THEN 'C' WHEN pg IN ('D','F') THEN 'DF' ELSE 'none' END pc,
         condition_id, won, p FROM a
), m AS (SELECT sc, pc, condition_id, count(*) n, sum(won-p) s FROM c GROUP BY 1,2,3),
t AS (SELECT sc, pc, sum(s)/sum(n) e FROM m GROUP BY 1,2)
SELECT t.sc study_cohort, t.pc pit_cohort, sum(m.n) trades, count(*) markets, round(100*t.e::numeric,2) edge_pts,
       round(100*1.96*sqrt(count(*)::float8/greatest(count(*)-1,1)*sum((m.s - t.e*m.n)^2))::numeric/sum(m.n),2) ci_half
FROM t JOIN m USING (sc, pc) GROUP BY t.sc, t.pc, t.e ORDER BY 1,2;

-- 4. Headline export: grade at the trade, per (grade, wallet, market) sufficient statistics.
--    Run three times, with [from, to) = [2026-06-01, 2026-07-25), [2026-07-25, 2026-09-20) and
--    [2026-09-20, 2026-10-07), each inside the replica's 60 s bound. aggregate.py pools them. The
--    two windows before 2026-09-20 ran without the grade_forward_at join, as
--    `false ex_known, NULL::text ex_grade`: the history's baseline completed at 2026-09-20 04:46 UTC.
--    In the last window, a buy the history cannot prove (113 of 6,915) falls back to the ranking row.
WITH b AS MATERIALIZED (
  SELECT w.trader_id, w.condition_id, w.traded_at, w.price_num::float8 p, w.usdc_notional_num::float8 usd,
         coalesce(w.category, '(none)') cat, (w.outcome_index = mo.winning_outcome)::int won
  FROM whale_alerts w JOIN market_outcomes mo ON mo.condition_id = w.condition_id
  WHERE w.platform = 'polymarket' AND w.side = 0
    AND w.traded_at >= '2026-09-20' AND w.traded_at < '2026-10-07'
    AND w.usdc_notional_num >= 10000 AND mo.winning_outcome IN (0, 1)
    AND mo.resolved_at > w.traded_at AND w.price_num BETWEEN 0.02 AND 0.98
), a AS MATERIALIZED (
  SELECT b.*, ga.known ex_known, ga.grade ex_grade,
         (SELECT tr.grade FROM trader_rankings tr
          WHERE tr.trader_id = b.trader_id AND tr.date <= b.traded_at::date AND tr.computed_at <= b.traded_at
          ORDER BY tr.date DESC LIMIT 1) pit_grade
  FROM b CROSS JOIN LATERAL grade_forward_at(b.trader_id, b.traded_at) ga
)
SELECT CASE WHEN ex_known THEN 'exact' ELSE 'pit' END src,
       coalesce(CASE WHEN ex_known THEN ex_grade ELSE pit_grade END, 'none') g,
       least(width_bucket(p, 0.0, 1.0, 5), 5) pb, cat, trader_id, left(condition_id, 18) mkt,
       count(*) n, sum(won - p) s, sum(won) wins, sum(p) sp, sum(usd) usd
FROM a GROUP BY 1, 2, 3, 4, 5, 6;

-- 5. Month-start export: the grade written before July 1, August 1 and September 1, scored on
--    the wallet's buys in the next 30 days. aggregate.py pools the three origins with wallets
--    clustered across them. A June 1 origin has no ranking row written before it that was never
--    rewritten, so every wallet reads as ungraded there.
WITH o AS (SELECT t::timestamptz t FROM unnest(ARRAY['2026-06-01','2026-07-01','2026-08-01','2026-09-01']::date[]) t),
f AS MATERIALIZED (
  SELECT o.t, w.trader_id, w.condition_id, w.price_num::float8 p, w.usdc_notional_num::float8 usd,
         (w.outcome_index = mo.winning_outcome)::int won
  FROM o JOIN whale_alerts w ON w.traded_at >= o.t AND w.traded_at < o.t + interval '30 days'
  JOIN market_outcomes mo ON mo.condition_id = w.condition_id
  WHERE w.platform = 'polymarket' AND w.side = 0 AND w.usdc_notional_num >= 10000
    AND mo.winning_outcome IN (0, 1) AND mo.resolved_at > w.traded_at AND w.price_num BETWEEN 0.02 AND 0.98
), fw AS MATERIALIZED (SELECT DISTINCT t, trader_id FROM f),
g AS MATERIALIZED (
  SELECT fw.t, fw.trader_id, coalesce((SELECT tr.grade FROM trader_rankings tr
           WHERE tr.trader_id = fw.trader_id AND tr.date <= fw.t::date AND tr.computed_at <= fw.t
           ORDER BY tr.date DESC LIMIT 1), 'none') grade
  FROM fw
)
SELECT f.t::date origin, g.grade g, f.trader_id, left(f.condition_id, 18) mkt,
       count(*) n, sum(f.won - f.p) s, sum(f.won) wins, sum(f.p) sp, sum(f.usd) usd
FROM f JOIN g USING (t, trader_id) GROUP BY 1, 2, 3, 4;
