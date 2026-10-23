-- Grade vs price paid, Polymarket large sports and esports buys. Run of 2026-10-23.
--
-- Read-only, against the production read replica (0xinsider's scripts/prod-read.sh wraps each
-- statement in BEGIN READ ONLY ... ROLLBACK with a 60 s statement timeout; query 5 ran with
-- --heavy, which skips only its plan-cost gate). Every statement below is the text that produced
-- results.md. Nothing is written.
--
-- WHAT CHANGED FROM 2026-10-07 (2026-10-07-all-markets/queries.sql).
-- 1. The universe. 0xinsider grades wallets on sports and esports markets only since
--    2026-10-22 11:32 UTC (migration 4390), so every query adds the grade's own market rule:
--      AND EXISTS (SELECT 1 FROM market_canonical mc WHERE mc.condition_id = w.condition_id
--                  AND is_provider_sports_market(mc.provider_game_id, mc.sports_market_type, mc.category))
-- 2. The window runs to 2026-10-22 (traded_at < 2026-10-23).
-- 3. Query 6, new: the buys after the basis switch, the only ones whose grade was computed on the
--    sports and esports basis.
-- The grade lookup, the price and settlement filters and the intervals are the 2026-10-07 ones.
-- Queries 1 to 3 (the September look-ahead, measured) are in 2026-10-07-all-markets/queries.sql;
-- the numbering here continues from them.
--
-- Grade at the trade:
--   - from 2026-09-20 04:46 UTC, when 0xinsider's grade history baseline completed, the grade the
--     wallet showed when the order filled (grade_forward_at, known = true);
--   - before that, the latest ranking row dated on or before the trade day AND last written at or
--     before the trade (tr.computed_at <= traded_at). Never drop the computed_at bound: without it
--     the query reintroduces the look-ahead.
--
-- Edge = share of buys whose side won minus average price paid, in percentage points.

-- 4. Headline export: grade at the trade, per (grade, wallet, market) sufficient statistics.
--    Run three times, with [from, to) = [2026-06-01, 2026-07-25), [2026-07-25, 2026-09-20) and
--    [2026-09-20, 2026-10-23), each inside the replica's 60 s bound (32,925, 14,711 and 9,801 rows).
--    aggregate.py pools them. The two windows before 2026-09-20 ran without the grade_forward_at
--    join: their `a` CTE is
--      SELECT b.*, false ex_known, NULL::text ex_grade, (SELECT tr.grade ...) pit_grade FROM b
--    because the history's baseline completed at 2026-09-20 04:46 UTC. In the last window, a buy
--    the history cannot prove (175 of 12,802) falls back to the ranking row.
WITH b AS MATERIALIZED (
  SELECT w.trader_id, w.condition_id, w.traded_at, w.price_num::float8 p, w.usdc_notional_num::float8 usd,
         coalesce(w.category, '(none)') cat, (w.outcome_index = mo.winning_outcome)::int won
  FROM whale_alerts w JOIN market_outcomes mo ON mo.condition_id = w.condition_id
  WHERE w.platform = 'polymarket' AND w.side = 0
    AND w.traded_at >= '2026-09-20' AND w.traded_at < '2026-10-23'
    AND w.usdc_notional_num >= 10000 AND mo.winning_outcome IN (0, 1)
    AND mo.resolved_at > w.traded_at AND w.price_num BETWEEN 0.02 AND 0.98
    AND EXISTS (SELECT 1 FROM market_canonical mc WHERE mc.condition_id = w.condition_id
                AND is_provider_sports_market(mc.provider_game_id, mc.sports_market_type, mc.category))
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
--    the wallet's buys in the next 30 days (47,765 rows). aggregate.py pools the three origins with
--    wallets clustered across them. A June 1 origin has no ranking row written before it that was
--    never rewritten, so every wallet reads as ungraded there.
WITH o AS (SELECT t::timestamptz t FROM unnest(ARRAY['2026-06-01','2026-07-01','2026-08-01','2026-09-01']::date[]) t),
f AS MATERIALIZED (
  SELECT o.t, w.trader_id, w.condition_id, w.price_num::float8 p, w.usdc_notional_num::float8 usd,
         (w.outcome_index = mo.winning_outcome)::int won
  FROM o JOIN whale_alerts w ON w.traded_at >= o.t AND w.traded_at < o.t + interval '30 days'
  JOIN market_outcomes mo ON mo.condition_id = w.condition_id
  WHERE w.platform = 'polymarket' AND w.side = 0 AND w.usdc_notional_num >= 10000
    AND mo.winning_outcome IN (0, 1) AND mo.resolved_at > w.traded_at AND w.price_num BETWEEN 0.02 AND 0.98
    AND EXISTS (SELECT 1 FROM market_canonical mc WHERE mc.condition_id = w.condition_id
                AND is_provider_sports_market(mc.provider_game_id, mc.sports_market_type, mc.category))
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

-- 6. The buys after the basis switch, 2026-10-22 11:32:04 UTC to the end of the window, by the
--    grade the history proves at the fill ('unproven' when it cannot).
WITH b AS MATERIALIZED (
  SELECT w.trader_id, w.condition_id, w.traded_at, w.price_num::float8 p,
         (w.outcome_index = mo.winning_outcome)::int won
  FROM whale_alerts w JOIN market_outcomes mo ON mo.condition_id = w.condition_id
  WHERE w.platform = 'polymarket' AND w.side = 0
    AND w.traded_at >= '2026-10-22 11:32:04+00' AND w.traded_at < '2026-10-23'
    AND w.usdc_notional_num >= 10000 AND mo.winning_outcome IN (0, 1)
    AND mo.resolved_at > w.traded_at AND w.price_num BETWEEN 0.02 AND 0.98
    AND EXISTS (SELECT 1 FROM market_canonical mc WHERE mc.condition_id = w.condition_id
                AND is_provider_sports_market(mc.provider_game_id, mc.sports_market_type, mc.category))
), a AS MATERIALIZED (
  SELECT b.*, CASE WHEN NOT ga.known THEN 'unproven'
                   WHEN ga.grade IN ('S','A') THEN 'S/A' WHEN ga.grade = 'B' THEN 'B'
                   WHEN ga.grade IN ('C','D','F') THEN 'C-F' ELSE 'none' END bk
  FROM b CROSS JOIN LATERAL grade_forward_at(b.trader_id, b.traded_at) ga
)
SELECT bk, count(*) trades, count(DISTINCT trader_id) wallets, count(DISTINCT condition_id) markets,
       round(100 * avg(won)::numeric, 2) won_pct, round(100 * avg(p)::numeric, 2) price_pct,
       round(100 * (sum(won - p) / count(*))::numeric, 2) edge
FROM a GROUP BY ROLLUP (bk) ORDER BY array_position(ARRAY['S/A','B','C-F','none','unproven'], bk) NULLS LAST;
