-- #22191. The sports studies' grade splits, re-measured with the grade each wallet held at the trade.
--
-- WHY. The September studies (sharp-money.sql, timing.sql, fade-crowd.sql, over-under.sql, spreads.sql,
-- cash-out.sql and soccer-draws.sql in this folder) took each buy's grade from the latest trader_rankings row dated on or before the trade day. 0xinsider
-- updates a wallet's latest ranking row in place when it recomputes the grade and sets computed_at = NOW(), so
-- that row usually held a grade written after the trade (section 7 measures it: 99.4% of the S, A and B buys
-- in the sharp-money universe). The all-category grade study made the same correction on the same day (#22175).
--
-- THE GRADE AT THE TRADE. From 2026-09-20 (when the grade history baseline completed), the grade the wallet
-- showed when the order filled: grade_forward_at(trader_id, traded_at) with known = true. Otherwise the latest
-- ranking row dated on or before the trade day AND last written at or before the trade (computed_at <=
-- traded_at). Never drop the computed_at bound: without it the query reintroduces the look-ahead. Outcomes are
-- winning_outcome IN (0, 1); the September queries used IS NOT NULL, which scored void (-1) and unresolved (-2)
-- markets as losses.
--
-- INTERVALS. 1.96 cluster-robust (CR1) standard errors, clustered by market, by wallet and by game (the event:
-- markets on one game settle on one result); the widest of the three is reported. The September intervals were
-- market bootstraps (game bootstraps for the totals and spreads studies).
--
-- WHERE IT RAN. On a Neon child branch of production forked at 14:18 UTC on 2026-10-07
-- (claude17-22191-sports-pit, deleted after the run), through ./scripts/neon-child-branch.sh query -f <this file>.
-- The committed output is one end-to-end run of this file (its run_at line is the start). The CREATE TABLE statements write
-- only to that scratch branch; nothing here writes to production. Output:
-- grade-at-trade-2026-10-07-output.txt and -stats.csv beside this file.
--
-- attr 'pub' in the tables below is the September lookup on the September universe, kept for comparison;
-- attr 'pit' is the corrected attribution and the only one the pages publish.

-- ===== 0. Base table: every large-trade alert (buy or sell) on a sports market, 2026-06-01 .. 2026-10-06 =====
DROP TABLE IF EXISTS s22191 CASCADE;
select now() as run_at;
CREATE TABLE s22191 AS
WITH b AS MATERIALIZED (
  SELECT w.id, w.trader_id, w.condition_id, w.traded_at, w.side, w.outcome_index,
         w.price_num::float8 p, w.usdc_notional_num::float8 usd, w.category wcat,
         m.category mcat, m.sports_market_type mtype, m.game_start_time ko, m.outcome_yes, m.outcome_no,
         m.title, m.group_item_title git, m.event_slug, m.line,
         mo.winning_outcome wo, mo.resolved_at
  FROM whale_alerts w
  JOIN market_outcomes mo ON mo.condition_id = w.condition_id
  LEFT JOIN markets m ON m.condition_id = w.condition_id
  WHERE w.platform = 'polymarket' AND w.side IN (0, 1)
    AND w.traded_at >= '2026-06-01' AND w.traded_at < '2026-10-07'
    AND (w.category IN ('Soccer','NBA','Esports','Tennis','Baseball','Hockey','Basketball','Cricket',
                        'MMA','NFL','Golf','WNBA','Formula 1','Boxing','NCAAF','NCAAB','Table Tennis',
                        'NBA Summer League','CFL','Sports','Big Game','Pickleball')
         OR m.category IN ('NFL','NCAAF','NBA','Basketball','WNBA','Baseball','Hockey','Soccer'))
    AND mo.winning_outcome IS NOT NULL AND mo.resolved_at > w.traded_at
    AND w.price_num BETWEEN 0.02 AND 0.98
)
SELECT b.*, (b.outcome_index = b.wo)::int won,
       s.grade pub_grade, s.computed_at pub_computed_at,
       (SELECT tr.grade FROM trader_rankings tr
         WHERE tr.trader_id = b.trader_id AND tr.date <= b.traded_at::date AND tr.computed_at <= b.traded_at
         ORDER BY tr.date DESC LIMIT 1) pit_grade
FROM b
LEFT JOIN LATERAL (
  SELECT tr.grade, tr.computed_at FROM trader_rankings tr
  WHERE tr.trader_id = b.trader_id AND tr.date <= b.traded_at::date
  ORDER BY tr.date DESC LIMIT 1) s ON true;
ALTER TABLE s22191 ADD COLUMN fwd_grade text, ADD COLUMN fwd_known boolean;
UPDATE s22191 s SET (fwd_grade, fwd_known) =
  (SELECT ga.grade, ga.known FROM grade_forward_at(s.trader_id, s.traded_at) ga)
WHERE s.traded_at >= '2026-09-20';
ANALYZE s22191;
select side, count(*) n, min(traded_at), max(traded_at), count(*) filter (where pub_grade is not null) pub_graded,
       count(*) filter (where pit_grade is not null) pit_graded, count(*) filter (where fwd_known) fwd_known
from s22191 group by 1 order by 1;

-- ===== 1. Both attributions, and one observation table per study cut =====
DROP TABLE IF EXISTS ga CASCADE;
CREATE TABLE ga AS
SELECT s.*, 'pub'::text attr, s.pub_grade g FROM s22191 s
UNION ALL
SELECT s.*, 'pit', CASE WHEN s.traded_at >= '2026-09-20' AND s.fwd_known THEN s.fwd_grade ELSE s.pit_grade END
FROM s22191 s WHERE s.wo IN (0, 1);
ALTER TABLE ga ADD COLUMN coh text, ADD COLUMN letter text, ADD COLUMN sports22 boolean, ADD COLUMN ev text;
UPDATE ga SET coh = CASE WHEN g IN ('S','A','B') THEN 'S/A/B' WHEN g = 'C' THEN 'C' WHEN g IN ('D','F') THEN 'D/F' ELSE 'no grade' END,
              letter = coalesce(g, 'none'),
              ev = coalesce(regexp_replace(event_slug, '-more-markets$', ''), condition_id),
              sports22 = wcat IN ('Soccer','NBA','Esports','Tennis','Baseball','Hockey','Basketball','Cricket','MMA','NFL','Golf','WNBA',
                                  'Formula 1','Boxing','NCAAF','NCAAB','Table Tennis','NBA Summer League','CFL','Sports','Big Game','Pickleball');
ANALYZE ga;

DROP TABLE IF EXISTS obs;
CREATE TABLE obs AS
WITH sharp AS (SELECT * FROM ga WHERE side = 0 AND sports22 AND traded_at < '2026-09-12'),
timing AS (SELECT *, extract(epoch from (ko - traded_at)) / 3600.0 h FROM ga WHERE side = 0 AND sports22 AND traded_at < '2026-09-12' AND ko IS NOT NULL),
ou AS (SELECT * FROM ga WHERE side = 0 AND sports22 AND traded_at < '2026-09-14' AND mtype = 'totals' AND outcome_yes = 'Over' AND outcome_no = 'Under'),
sp AS (SELECT * FROM ga WHERE side = 0 AND traded_at < '2026-09-14' AND outcome_index IN (0, 1) AND wo IN (0, 1)
         AND mtype = 'spreads' AND ko < '2026-09-14'
         AND mcat IN ('NFL','NCAAF','NBA','Basketball','WNBA','Baseball','Hockey','Soccer')
         AND title ~ '^Spread: .* \(-[0-9.]+\)$' AND substring(title from '^Spread: (.*) \(-[0-9.]+\)$') = outcome_yes),
co AS (SELECT * FROM ga WHERE side = 1 AND sports22 AND traded_at < '2026-09-14'),
dr AS (SELECT *, CASE WHEN (git LIKE 'Draw (%' OR title LIKE '%end in a draw%') THEN 'draw' ELSE 'team' END leg
       FROM ga WHERE side = 0 AND wcat = 'Soccer' AND traded_at < '2026-09-14' AND mcat = 'Soccer' AND mtype = 'moneyline'
         AND outcome_yes = 'Yes' AND outcome_no = 'No' AND ko >= '2026-04-02' AND ko < '2026-09-14' AND wo IN (0, 1)),
nba AS (SELECT * FROM ga WHERE side = 0 AND wcat = 'NBA' AND traded_at < '2026-09-14')
SELECT 'sharp' study, attr, 'cohort' cut, coh cohort, trader_id, condition_id, ev, won, p, usd FROM sharp
UNION ALL SELECT 'sharp', attr, 'letter', letter, trader_id, condition_id, ev, won, p, usd FROM sharp
UNION ALL SELECT 'sharp', attr, 'sport:' || wcat, coh, trader_id, condition_id, ev, won, p, usd FROM sharp
UNION ALL SELECT 'sharp', attr, 'band:' || CASE WHEN p < 0.2 THEN 'p1' WHEN p < 0.4 THEN 'p2' WHEN p < 0.6 THEN 'p3' WHEN p < 0.8 THEN 'p4' ELSE 'p5' END, coh, trader_id, condition_id, ev, won, p, usd FROM sharp
UNION ALL SELECT 'sharp', attr, 'mtype:' || mtype, coh, trader_id, condition_id, ev, won, p, usd FROM sharp WHERE mtype IN ('moneyline','spreads','totals','child_moneyline')
UNION ALL SELECT 'sharp', attr, 'phase:' || CASE WHEN traded_at < ko THEN 'pre' ELSE 'live' END, coh, trader_id, condition_id, ev, won, p, usd FROM sharp WHERE ko IS NOT NULL
UNION ALL SELECT 'sharp', attr, 'month:' || to_char(traded_at, 'MM'), coh, trader_id, condition_id, ev, won, p, usd FROM sharp
UNION ALL SELECT 'sharp', attr, 'tenk', coh, trader_id, condition_id, ev, won, p, usd FROM sharp WHERE usd >= 10000
UNION ALL SELECT 'sharp_ext', attr, 'cohort', coh, trader_id, condition_id, ev, won, p, usd FROM ga WHERE side = 0 AND sports22
UNION ALL SELECT 'sharp_ext', attr, 'letter', letter, trader_id, condition_id, ev, won, p, usd FROM ga WHERE side = 0 AND sports22
UNION ALL SELECT 'timing', attr, 'bucket:' || CASE WHEN h > 168 THEN 't1' WHEN h > 24 THEN 't2' WHEN h > 6 THEN 't3' WHEN h > 1 THEN 't4'
                                             WHEN h > 0 THEN 't5' WHEN h > -1 THEN 't6' WHEN h > -2 THEN 't7' ELSE 't8' END,
                 coh, trader_id, condition_id, ev, won, p, usd FROM timing
UNION ALL SELECT 'timing', attr, 'mix:' || CASE WHEN h > 24 THEN 'dayplus' WHEN h > 0 THEN 'sameday' ELSE 'inplay' END,
                 coh, trader_id, condition_id, ev, won, p, usd FROM timing
UNION ALL SELECT 'ou', attr, 'side:' || CASE WHEN outcome_index = 0 THEN 'Over' ELSE 'Under' END, coh, trader_id, condition_id, ev, won, p, usd FROM ou
UNION ALL SELECT 'spreads', attr, 'side:' || CASE WHEN outcome_index = 0 THEN 'lay' ELSE 'take' END, coh, trader_id, condition_id, ev, won, p, usd FROM sp
UNION ALL SELECT 'cashout', attr, 'grp:' || CASE WHEN p < 0.2 THEN 'under20' WHEN p < 0.8 THEN '20to80' ELSE '80plus' END, coh, trader_id, condition_id, ev, won, p, usd FROM co
UNION ALL SELECT 'cashout', attr, 'grp:all', coh, trader_id, condition_id, ev, won, p, usd FROM co
UNION ALL SELECT 'draws', attr, leg || ':' || CASE WHEN outcome_index = 0 THEN 'Yes' ELSE 'No' END, coh, trader_id, condition_id, ev, won, p, usd FROM dr
UNION ALL SELECT 'nba', attr, 'cohort', coh, trader_id, condition_id, ev, won, p, usd FROM nba;
ANALYZE obs;
select study, attr, count(*) from obs group by 1,2 order by 1,2;

-- ===== 2. Per-cut statistics (the -stats.csv export is: select * from sv order by study, cut, cohort, attr desc) =====
DROP TABLE IF EXISTS stats CASCADE;
CREATE TABLE stats AS
WITH t AS (
  SELECT study, attr, cut, cohort, count(*) n, count(DISTINCT trader_id) wl, count(DISTINCT condition_id) mk,
         count(DISTINCT ev) gm, sum(usd) usd, avg(won::float8) wr, avg(p) pr, sum(won - p) / count(*) e,
         sum(usd * (won / p - 1)) / sum(usd) roi
  FROM obs GROUP BY 1, 2, 3, 4),
m AS (SELECT study, attr, cut, cohort, condition_id k, count(*) n, sum(won - p) s FROM obs GROUP BY 1, 2, 3, 4, 5),
w AS (SELECT study, attr, cut, cohort, trader_id::text k, count(*) n, sum(won - p) s FROM obs GROUP BY 1, 2, 3, 4, 5),
g AS (SELECT study, attr, cut, cohort, ev k, count(*) n, sum(won - p) s FROM obs GROUP BY 1, 2, 3, 4, 5),
c AS (SELECT 'm' kind, * FROM m UNION ALL SELECT 'w', * FROM w UNION ALL SELECT 'g', * FROM g),
v AS (SELECT c.kind, c.study, c.attr, c.cut, c.cohort,
             1.96 * sqrt(count(*)::float8 / greatest(count(*) - 1, 1) * sum((c.s - t.e * c.n) ^ 2)) / t.n v
      FROM c JOIN t USING (study, attr, cut, cohort) GROUP BY 1, 2, 3, 4, 5, t.n)
SELECT t.*, vm.v vm, vw.v vw, vg.v vg FROM t
JOIN v vm ON vm.kind = 'm' AND (vm.study, vm.attr, vm.cut, vm.cohort) = (t.study, t.attr, t.cut, t.cohort)
JOIN v vw ON vw.kind = 'w' AND (vw.study, vw.attr, vw.cut, vw.cohort) = (t.study, t.attr, t.cut, t.cohort)
JOIN v vg ON vg.kind = 'g' AND (vg.study, vg.attr, vg.cut, vg.cohort) = (t.study, t.attr, t.cut, t.cohort);
CREATE OR REPLACE VIEW sv AS
SELECT study, attr, cut, cohort, n, wl, mk, gm, round((usd / 1e6)::numeric, 1) musd, round((100 * wr)::numeric, 1) win,
       round((100 * pr)::numeric, 1) price, round((100 * e)::numeric, 2) edge, round((100 * roi)::numeric, 2) roi,
       round((100 * vm)::numeric, 2) ci_m, round((100 * vw)::numeric, 2) ci_w, round((100 * vg)::numeric, 2) ci_g,
       round((100 * greatest(vm, vw, vg))::numeric, 2) ci,
       round((100 * (e - greatest(vm, vw, vg)))::numeric, 2) lo, round((100 * (e + greatest(vm, vw, vg)))::numeric, 2) hi
FROM stats;
select count(*) from stats;

-- ===== 3. S/A/B minus D/F gaps =====
WITH o AS (SELECT study, attr, cut, cohort, trader_id, condition_id, ev, won, p FROM obs
           WHERE cohort IN ('S/A/B','D/F') AND ((study = 'sharp' AND cut IN ('cohort','phase:pre','phase:live','tenk'))
                OR (study = 'sharp_ext' AND cut = 'cohort') OR (study = 'timing' AND cut = 'bucket:t6'))),
t AS (SELECT study, attr, cut, cohort, count(*) n, sum(won - p) / count(*) e FROM o GROUP BY 1, 2, 3, 4),
oi AS (SELECT o.*, CASE WHEN o.cohort = 'S/A/B' THEN 1 ELSE -1 END * (o.won - o.p - t.e) / t.n infl
       FROM o JOIN t USING (study, attr, cut, cohort)),
u AS (SELECT 'm' kind, study, attr, cut, condition_id k, sum(infl) u FROM oi GROUP BY 1, 2, 3, 4, 5
      UNION ALL SELECT 'w', study, attr, cut, trader_id::text, sum(infl) FROM oi GROUP BY 1, 2, 3, 4, 5
      UNION ALL SELECT 'g', study, attr, cut, ev, sum(infl) FROM oi GROUP BY 1, 2, 3, 4, 5),
v AS (SELECT kind, study, attr, cut, 1.96 * sqrt(count(*)::float8 / (count(*) - 1) * sum(u ^ 2)) v FROM u GROUP BY 1, 2, 3, 4),
vv AS (SELECT study, attr, cut, max(v) FILTER (WHERE kind = 'm') vm, max(v) FILTER (WHERE kind = 'w') vw,
              max(v) FILTER (WHERE kind = 'g') vg FROM v GROUP BY 1, 2, 3),
d AS (SELECT study, attr, cut, max(e) FILTER (WHERE cohort = 'S/A/B') - max(e) FILTER (WHERE cohort = 'D/F') gap FROM t GROUP BY 1, 2, 3)
SELECT d.study, d.attr, d.cut, round((100 * d.gap)::numeric, 2) gap, round((100 * vm)::numeric, 2) ci_m,
       round((100 * vw)::numeric, 2) ci_w, round((100 * vg)::numeric, 2) ci_g,
       round((100 * (d.gap - greatest(vm, vw, vg)))::numeric, 2) lo, round((100 * (d.gap + greatest(vm, vw, vg)))::numeric, 2) hi
FROM d JOIN vv USING (study, attr, cut) ORDER BY 1, 3, 2 DESC;

-- ===== 4. Fading the crowd (fade-crowd.sql), both attributions =====
DROP TABLE IF EXISTS fb CASCADE; DROP TABLE IF EXISTS fmk CASCADE;
CREATE TABLE fb AS
SELECT attr, trader_id, condition_id, ev, traded_at, outcome_index, p price_num, usd usdc_notional_num, wcat category, mtype sports_market_type, wo winning_outcome,
       CASE WHEN g IN ('S','A','B') THEN 'sab' WHEN g IN ('D','F') THEN 'df' ELSE 'other' END cohort
FROM ga WHERE side = 0 AND sports22 AND traded_at < '2026-09-13'
  AND (mtype IN ('moneyline','child_moneyline','spreads','totals') OR mtype IS NULL)
  AND ko IS NOT NULL AND traded_at < ko;
CREATE TABLE fmk AS
select attr, condition_id, winning_outcome, max(ev) ev, max(sports_market_type) mtype, max(category) category, min(traded_at) first_buy,
  sum(usdc_notional_num) filter (where cohort='df' and outcome_index=0) df0, sum(usdc_notional_num) filter (where cohort='df' and outcome_index=1) df1,
  sum(usdc_notional_num) filter (where cohort='sab' and outcome_index=0) sab0, sum(usdc_notional_num) filter (where cohort='sab' and outcome_index=1) sab1,
  count(*) filter (where cohort='df') n_df, count(*) filter (where cohort='sab') n_sab,
  count(distinct trader_id) filter (where cohort='df') w_df, count(distinct trader_id) filter (where cohort='sab') w_sab,
  avg(price_num) filter (where cohort='df' and outcome_index=0) dfp0, avg(price_num) filter (where cohort='df' and outcome_index=1) dfp1,
  avg(price_num) filter (where cohort='sab' and outcome_index=0) sabp0, avg(price_num) filter (where cohort='sab' and outcome_index=1) sabp1,
  avg(price_num) filter (where outcome_index=0) p0, avg(price_num) filter (where outcome_index=1) p1
from fb group by 1,2,3;
CREATE VIEW fdfl AS
select *, coalesce(df0,0)+coalesce(df1,0) dft,
       case when coalesce(df0,0) >= coalesce(df1,0) then 0 else 1 end side,
       case when coalesce(df0,0) >= coalesce(df1,0) then dfp0 else dfp1 end side_price,
       case when coalesce(df0,0) >= coalesce(df1,0) then p1 else p0 end other_side_price_observed,
       greatest(coalesce(df0,0),coalesce(df1,0))/(coalesce(df0,0)+coalesce(df1,0)) lean
from fmk where coalesce(df0,0)+coalesce(df1,0) >= 5000 and n_df >= 2;
CREATE VIEW fsabl AS
select *, coalesce(sab0,0)+coalesce(sab1,0) sabt,
       case when coalesce(sab0,0) >= coalesce(sab1,0) then 0 else 1 end side,
       case when coalesce(sab0,0) >= coalesce(sab1,0) then sabp0 else sabp1 end side_price,
       greatest(coalesce(sab0,0),coalesce(sab1,0))/(coalesce(sab0,0)+coalesce(sab1,0)) lean
from fmk where coalesce(sab0,0)+coalesce(sab1,0) >= 5000 and n_sab >= 2;

\echo 1. sample
select attr, count(*) buys, count(distinct trader_id) wallets, count(distinct condition_id) markets, round((sum(usdc_notional_num)/1e9)::numeric,2) bn,
       count(*) filter (where cohort='df') df_buys, count(*) filter (where cohort='sab') sab_buys, count(*) filter (where cohort='other') other_buys
from fb group by 1 order by 1 desc;
select attr, count(*) filter (where n_df>0) with_df, count(*) filter (where n_sab>0) with_sab, count(*) filter (where n_df>0 and n_sab>0) with_both from fmk group by 1 order by 1 desc;
\echo 2. baseline
select attr, cohort, count(*) buys, round((avg(price_num)*100)::numeric,1) price, round((avg((outcome_index=winning_outcome)::int)*100)::numeric,1) win,
       round(((avg((outcome_index=winning_outcome)::int) - avg(price_num))*100)::numeric,2) edge
from fb group by 1,2 order by 2,1 desc;
\echo 3. df bands (ci = 1.96 x market-level SE; one row per market)
select attr, case when lean >= 0.9 then 'a90' when lean >= 0.7 then 'b70' else 'c' end band, count(*) markets, round(avg(w_df),1) wallets, round((sum(dft)/1e6)::numeric,1) musd,
       round((avg(side_price)*100)::numeric,1) price, round((100.0*avg((side=winning_outcome)::int))::numeric,1) won,
       round(((avg((side=winning_outcome)::int) - avg(side_price))*100)::numeric,2) edge,
       round((196*stddev_samp((side=winning_outcome)::int - side_price)/sqrt(count(*)))::numeric,2) ci,
       round((100*avg(case when side<>winning_outcome then (1/(1-side_price)-1) else -1 end))::numeric,2) fade_roi,
       round((100*avg(case when side=winning_outcome then (1/side_price-1) else -1 end))::numeric,2) follow_roi
from fdfl group by 1,2 order by 2,1 desc;
\echo 4. sab bands
select attr, case when lean >= 0.9 then 'a90' when lean >= 0.7 then 'b70' else 'c' end band, count(*) markets, round(avg(w_sab),1) wallets, round((sum(sabt)/1e6)::numeric,1) musd,
       round((avg(side_price)*100)::numeric,1) price, round((100.0*avg((side=winning_outcome)::int))::numeric,1) won,
       round(((avg((side=winning_outcome)::int) - avg(side_price))*100)::numeric,2) edge,
       round((196*stddev_samp((side=winning_outcome)::int - side_price)/sqrt(count(*)))::numeric,2) ci,
       round((100*avg(case when side=winning_outcome then (1/side_price-1) else -1 end))::numeric,2) follow_roi
from fsabl group by 1,2 order by 2,1 desc;
\echo 5. agreement
with both_ as (
 select m.*, case when coalesce(df0,0) >= coalesce(df1,0) then 0 else 1 end df_side, case when coalesce(sab0,0) >= coalesce(sab1,0) then 0 else 1 end sab_side,
        case when coalesce(df0,0) >= coalesce(df1,0) then dfp0 else dfp1 end df_price, case when coalesce(sab0,0) >= coalesce(sab1,0) then sabp0 else sabp1 end sab_price
 from fmk m where coalesce(df0,0)+coalesce(df1,0) >= 5000 and coalesce(sab0,0)+coalesce(sab1,0) >= 5000)
select attr, case when df_side=sab_side then 'agree' else 'disagree' end agreement, count(*) markets,
       round((avg(sab_price)*100)::numeric,1) sab_price, round((100.0*avg((sab_side=winning_outcome)::int))::numeric,1) sab_won,
       round(((avg((sab_side=winning_outcome)::int) - avg(sab_price))*100)::numeric,2) sab_edge,
       round((avg(df_price)*100)::numeric,1) df_price, round((100.0*avg((df_side=winning_outcome)::int))::numeric,1) df_won,
       round(((avg((df_side=winning_outcome)::int) - avg(df_price))*100)::numeric,2) df_edge
from both_ group by 1,2 order by 2,1 desc;
\echo 6. crowd side
select attr, case when side_price >= 0.5 then 'fav' else 'dog' end crowd_side, count(*) markets,
       round((avg(side_price)*100)::numeric,1) price, round((100.0*avg((side=winning_outcome)::int))::numeric,1) won,
       round(((avg((side=winning_outcome)::int) - avg(side_price))*100)::numeric,2) edge,
       round((196*stddev_samp((side=winning_outcome)::int - side_price)/sqrt(count(*)))::numeric,2) ci,
       round((100*avg(case when side<>winning_outcome then (1/(1-side_price)-1) else -1 end))::numeric,2) fade_roi
from fdfl where lean >= 0.9 group by 1,2 order by 2,1 desc;
\echo 7. sport
select attr, category, count(*) markets, round((avg(side_price)*100)::numeric,1) price, round((100.0*avg((side=winning_outcome)::int))::numeric,1) won,
       round(((avg((side=winning_outcome)::int) - avg(side_price))*100)::numeric,2) edge
from fdfl where lean >= 0.9 group by 1,2 having count(*) >= 40 order by 2,1 desc;
\echo 8. market type
select attr, coalesce(mtype,'(untyped)') mt, count(*) markets, round((avg(side_price)*100)::numeric,1) price,
       round(((avg((side=winning_outcome)::int) - avg(side_price))*100)::numeric,2) edge
from fdfl where lean >= 0.9 group by 1,2 order by 2,1 desc;
\echo 9. month
select attr, to_char(first_buy,'MM') mo, count(*) markets, round((avg(side_price)*100)::numeric,1) price,
       round(((avg((side=winning_outcome)::int) - avg(side_price))*100)::numeric,2) edge
from fdfl where lean >= 0.9 group by 1,2 order by 2,1 desc;
\echo 10. floor
select attr, thr, count(*) markets, round((avg(side_price)*100)::numeric,1) price,
       round(((avg((side=winning_outcome)::int) - avg(side_price))*100)::numeric,2) edge,
       round((196*stddev_samp((side=winning_outcome)::int - side_price)/sqrt(count(*)))::numeric,2) ci,
       round((100*avg(case when side<>winning_outcome then (1/(1-side_price)-1) else -1 end))::numeric,2) fade_roi
from fdfl, unnest(array[5000,10000,25000,50000,100000]) thr where lean >= 0.9 and dft >= thr group by 1,2 order by 2,1 desc;
\echo 11. complement
select attr, count(*) markets, round((avg(1-side_price)*100)::numeric,2) complement_c, round((avg(other_side_price_observed)*100)::numeric,2) observed_c,
       round((avg(other_side_price_observed - (1-side_price))*100)::numeric,2) gap_c
from fdfl where lean >= 0.9 and other_side_price_observed is not null group by 1 order by 1 desc;
\echo 12. half-widths: one row per market, so the market-clustered half-width is the plain standard error; the
\echo     game-clustered one groups markets of the same game. The wider is reported.
WITH x AS (
  SELECT attr, 'df_' || CASE WHEN lean >= 0.9 THEN 'a90' WHEN lean >= 0.7 THEN 'b70' ELSE 'c' END grp, ev, (side = winning_outcome)::int - side_price v FROM fdfl
  UNION ALL SELECT attr, 'sab_' || CASE WHEN lean >= 0.9 THEN 'a90' WHEN lean >= 0.7 THEN 'b70' ELSE 'c' END, ev, (side = winning_outcome)::int - side_price FROM fsabl
  UNION ALL SELECT attr, 'df90_' || CASE WHEN side_price >= 0.5 THEN 'fav' ELSE 'dog' END, ev, (side = winning_outcome)::int - side_price FROM fdfl WHERE lean >= 0.9
  UNION ALL SELECT attr, 'df90_floor' || thr, ev, (side = winning_outcome)::int - side_price FROM fdfl, unnest(array[5000,10000,25000,50000,100000]) thr WHERE lean >= 0.9 AND dft >= thr),
t AS (SELECT attr, grp, count(*) n, avg(v) mu, stddev_samp(v) sd FROM x GROUP BY 1, 2),
g AS (SELECT x.attr, x.grp, x.ev, sum(x.v - t.mu) z FROM x JOIN t USING (attr, grp) GROUP BY 1, 2, 3),
gv AS (SELECT attr, grp, count(*) ng, sqrt(count(*)::float8 / greatest(count(*) - 1, 1) * sum(z ^ 2)) s FROM g GROUP BY 1, 2)
SELECT t.attr, t.grp, t.n markets, gv.ng games, round((100 * t.mu)::numeric, 2) edge, round((196 * t.sd / sqrt(t.n))::numeric, 2) ci_m,
       round((196 * gv.s / t.n)::numeric, 2) ci_g,
       round((100 * t.mu - greatest(196 * t.sd / sqrt(t.n), 196 * gv.s / t.n))::numeric, 2) lo,
       round((100 * t.mu + greatest(196 * t.sd / sqrt(t.n), 196 * gv.s / t.n))::numeric, 2) hi
FROM t JOIN gv USING (attr, grp) ORDER BY 2, 1 DESC;

-- ===== 5. The UFC and cricket guides' graded split (query 7 of the 0xinsider repository's
--           docs/research-articles/verification/2026-09-14-combat-cricket-guides.sql), and the
--           share of its attributions that read a ranking row written after the buy =====
WITH o AS (SELECT attr, wcat, CASE WHEN g IN ('S','A','B') THEN 'S/A/B' WHEN g IN ('D','F') THEN 'D/F' ELSE 'other' END coh,
                  trader_id, condition_id, ev, won, p, (pub_computed_at > traded_at) rewritten FROM ga
           WHERE side = 0 AND wcat IN ('MMA','Cricket') AND traded_at < '2026-09-15'),
t AS (SELECT attr, wcat, coh, count(*) n, count(DISTINCT trader_id) wl, avg(p) pr, sum(won - p) / count(*) e,
             avg(rewritten::int) rw FROM o GROUP BY 1, 2, 3),
c AS (SELECT 'm' kind, attr, wcat, coh, condition_id k, count(*) n, sum(won - p) s FROM o GROUP BY 1, 2, 3, 4, 5
      UNION ALL SELECT 'w', attr, wcat, coh, trader_id::text, count(*), sum(won - p) FROM o GROUP BY 1, 2, 3, 4, 5
      UNION ALL SELECT 'g', attr, wcat, coh, ev, count(*), sum(won - p) FROM o GROUP BY 1, 2, 3, 4, 5),
v AS (SELECT c.kind, c.attr, c.wcat, c.coh, 1.96 * sqrt(count(*)::float8 / greatest(count(*) - 1, 1) * sum((c.s - t.e * c.n) ^ 2)) / t.n v
      FROM c JOIN t USING (attr, wcat, coh) GROUP BY 1, 2, 3, 4, t.n)
SELECT t.attr, t.wcat, t.coh, t.n, t.wl, round((100 * t.pr)::numeric, 1) price, round((100 * t.e)::numeric, 2) edge,
       round((100 * max(v.v))::numeric, 2) ci, round((100 * (t.e - max(v.v)))::numeric, 2) lo, round((100 * (t.e + max(v.v)))::numeric, 2) hi,
       CASE WHEN t.attr = 'pub' THEN round((100 * t.rw)::numeric, 1) END pct_row_written_after_buy
FROM t JOIN v USING (attr, wcat, coh) WHERE t.coh <> 'other' GROUP BY t.attr, t.wcat, t.coh, t.n, t.wl, t.pr, t.e, t.rw ORDER BY 2, 3, 1 DESC;

-- ===== 6. The September lookup on the corrected universe (the correction tables' middle column) =====
WITH b AS (SELECT s.*, coalesce(pub_grade, 'none') l,
                  CASE WHEN pub_grade IN ('S','A','B') THEN 'S/A/B' WHEN pub_grade = 'C' THEN 'C' WHEN pub_grade IN ('D','F') THEN 'D/F' ELSE 'no grade' END pc,
                  CASE WHEN traded_at < ko THEN 'pre' WHEN ko IS NOT NULL THEN 'live' END ph
           FROM s22191 s
           WHERE side = 0 AND traded_at < '2026-09-12' AND wo IN (0, 1)
             AND wcat IN ('Soccer','NBA','Esports','Tennis','Baseball','Hockey','Basketball','Cricket','MMA','NFL','Golf','WNBA',
                          'Formula 1','Boxing','NCAAF','NCAAB','Table Tennis','NBA Summer League','CFL','Sports','Big Game','Pickleball'))
SELECT 'cohort' cut, pc k, count(*) n, round((100 * avg(won - p))::numeric, 2) edge FROM b GROUP BY pc
UNION ALL SELECT 'letter', l, count(*), round((100 * avg(won - p))::numeric, 2) FROM b WHERE l IN ('S','A','B','D','F') GROUP BY l
UNION ALL SELECT 'phase:' || ph, pc, count(*), round((100 * avg(won - p))::numeric, 2) FROM b WHERE ph IS NOT NULL AND pc IN ('S/A/B','D/F') GROUP BY ph, pc
ORDER BY 1, 2;

-- ===== 7. The look-ahead, measured; and the at-fill coverage from 2026-09-20 =====
WITH b AS (SELECT s.*, CASE WHEN pub_grade IN ('S','A','B') THEN 'S/A/B' WHEN pub_grade = 'C' THEN 'C' WHEN pub_grade IN ('D','F') THEN 'D/F' ELSE 'no grade' END pc,
                  CASE WHEN pit_grade IN ('S','A','B') THEN 'S/A/B' WHEN pit_grade = 'C' THEN 'C' WHEN pit_grade IN ('D','F') THEN 'D/F' ELSE 'no grade' END tc
           FROM s22191 s
           WHERE side = 0 AND traded_at < '2026-09-12' AND wo IN (0, 1)
             AND wcat IN ('Soccer','NBA','Esports','Tennis','Baseball','Hockey','Basketball','Cricket','MMA','NFL','Golf','WNBA',
                          'Formula 1','Boxing','NCAAF','NCAAB','Table Tennis','NBA Summer League','CFL','Sports','Big Game','Pickleball'))
SELECT 'rewritten' q, pc cohort, NULL::text to_cohort, count(*) n, round((100.0 * avg((pub_computed_at > traded_at)::int))::numeric, 1) pct, NULL::numeric edge
FROM b GROUP BY pc
UNION ALL
SELECT 'moved', pc, tc, count(*), NULL, round((100 * avg(won - p))::numeric, 2) FROM b WHERE pc <> tc AND pc IN ('S/A/B','D/F') AND tc IN ('S/A/B','D/F') GROUP BY pc, tc
UNION ALL
SELECT 'atfill', 'sports buys from 2026-09-20', NULL, count(*), round((100.0 * avg(fwd_known::int))::numeric, 1), NULL
FROM s22191 WHERE side = 0 AND traded_at >= '2026-09-20' AND wo IN (0, 1)
  AND wcat IN ('Soccer','NBA','Esports','Tennis','Baseball','Hockey','Basketball','Cricket','MMA','NFL','Golf','WNBA',
               'Formula 1','Boxing','NCAAF','NCAAB','Table Tennis','NBA Summer League','CFL','Sports','Big Game','Pickleball')
ORDER BY 1, 2, 3;

-- ===== 8. Every statistic, both attributions (the same rows as -stats.csv) =====
select * from sv order by study, cut, cohort, attr desc;
