-- #23731 (epic #23652). The soccer draws study (2026-09-13-sports-soccer-draws.sql.txt) re-run with a price-sum
-- filter, and the same filter applied to the soccer rows of four other studies.
--
-- WHY. Slice L3 (#23682, 2026-10-11-sports-playbook-guide-charts.sql.txt, queries 4, 4e and 4f) read the three
-- result prices of a soccer match (home win, draw, away win) at the last daily price-history point before kickoff,
-- and found 1,536 of 11,494 matches whose three Yes prices summed to a median $1.29, 799 of them with the draw at
-- 40c or more: quotes on books that did not hold together, not prices anyone traded at.
--
-- WHAT THE DRAWS STUDY PRICES. Not a price-history point. Its pricing half scores every large buy at the price it
-- filled at (whale_alerts.price_num), and "before kickoff" means traded_at < game_start_time (its query 6). So a
-- stale quote cannot enter its prices directly. What can enter is the match: a buy filled on a match whose book did
-- not hold together at kickoff. This file drops those matches and re-runs the pricing half, in the same run as the
-- unfiltered version, on the study's own window, so any difference is the filter's and not the data's.
--
-- THE FILTER. The study's legs (typed soccer moneyline markets with Yes/No outcomes, kickoffs 2026-04-02 to
-- 2026-09-13, settled Yes or No). Each leg's Yes price is its last outcome_price_snapshots point before kickoff, as
-- L3's query 4 read it (provider_timestamp before kickoff and no more than 36 hours before it). A match is TESTED
-- when it has one draw leg and two team legs, all three priced, at points no more than 2 hours apart. A tested
-- match HELD when its three prices summed to 95c to 105c, and is OFF otherwise; UNTESTED matches stay in, since
-- nothing says their book failed. Universe 'all' is the study as published; 'kept' drops the OFF matches.
-- Query 1 is the distribution the 5c tolerance is read from; query 9 shows 2c, 3c and 10c beside it.
--
-- OTHER STUDIES (query 11). Each prices large-buy fills, not a price-history point. Their soccer buys are linked
-- to a match by event_slug with '-more-markets' or '-halftime-result' removed, and the same OFF matches dropped:
-- both teams to score (2026-09-13-sports-btts-halftime.sql.txt query 9), over/under (2026-10-10-sports-over-under.sql.txt
-- queries 4 and 7), favorite-longshot (2026-10-10-sports-calibration.sql queries 2, 4 and 5) and fading the crowd
-- (2026-10-07-sports-grade-at-trade.sql section 4, 'pit' grades, soccer only).
--
-- WHERE IT RAN. On a Neon child branch of production (claude-18-23731-reruns, forked 14:56 UTC on 2026-10-11,
-- deleted after the runs) through ./scripts/neon-child-branch.sh query, read-only against production. The temp
-- tables live only in the session. Output: 2026-10-11-soccer-draws-price-sum-filter-output.txt; the market-level
-- export for the bootstrap: 2026-10-11-soccer-draws-price-sum-filter-market-edge.csv, and its intervals,
-- 2026-10-11-soccer-draws-price-sum-filter-bootstrap-output.txt (2026-09-13-sports-bootstrap.py, seed 20260913).
select now() as run_at, (select max(traded_at) from whale_alerts where traded_at > timestamptz '2026-10-09') latest_alert_on_branch;

-- The study's legs, with the key the price history is stored under.
create temp table legs as
select m.condition_id, md.condition_key, m.event_slug, m.game_start_time,
       case when (m.group_item_title like 'Draw (%' or m.title like '%end in a draw%') then 'draw' else 'team' end leg,
       mo.winning_outcome
from markets m
join market_outcomes mo on mo.condition_id = m.condition_id
left join market_dim md on md.condition_id = m.condition_id
where m.category = 'Soccer' and m.sports_market_type = 'moneyline'
  and m.outcome_yes = 'Yes' and m.outcome_no = 'No'
  and m.game_start_time >= timestamptz '2026-04-02' and m.game_start_time < timestamptz '2026-09-14'
  and mo.winning_outcome in (0, 1);
analyze legs;

-- Each leg's last Yes price-history point before kickoff (L3's query 4 rule).
create temp table legp as
select l.*, p.price, p.provider_timestamp,
       (p.price is not null and p.provider_timestamp >= l.game_start_time - interval '36 hours') priced
from legs l left join lateral (
  select o.price, o.provider_timestamp from outcome_price_snapshots o
  where o.condition_key = l.condition_key and o.outcome_index = 0
    and o.bucket_start >= l.game_start_time - interval '3 days' and o.bucket_start <= l.game_start_time
    and o.provider_timestamp < l.game_start_time
  order by o.provider_timestamp desc limit 1) p on true;

create temp table books as
select event_slug,
       count(*) filter (where leg = 'draw') draws, count(*) filter (where leg = 'team') teams,
       count(*) filter (where priced) priced_legs,
       sum(price) filter (where priced) total,
       max(provider_timestamp) filter (where priced) - min(provider_timestamp) filter (where priced) spread_t,
       max(price) filter (where priced and leg = 'draw') draw_price,
       bool_or(leg = 'draw' and winning_outcome = 0) drew
from legp group by 1;
alter table books add column tested boolean, add column book text;
update books set tested = (draws = 1 and teams = 2 and priced_legs = 3 and spread_t <= interval '2 hours');
update books set book = case when not tested then 'untested' when total between 0.95 and 1.05 then 'held' else 'off' end;
analyze books;

-- 0. Coverage: legs priced, and matches by class.
select (select count(*) from legp) legs, (select count(*) filter (where priced) from legp) legs_priced,
       count(*) matches, count(*) filter (where draws = 1 and teams = 2) complete,
       count(*) filter (where tested) tested, count(*) filter (where book = 'held') held, count(*) filter (where book = 'off') off,
       count(*) filter (where book = 'untested') untested
from books;

-- 1. The distribution the tolerance is read from: tested matches by their three prices' sum, in 1c bins.
select case when total < 0.90 then 'a. under 0.90' when total >= 1.20 then 'z. 1.20 and over'
            else 'm. ' || to_char(floor(total * 100) / 100, 'FM0.00') end sum_bin,
       count(*) matches
from books where tested group by 1 order by 1;
select p.q, round((percentile_cont(p.q) within group (order by b.total) * 100)::numeric, 1) total_c
from books b cross join (values (0.01), (0.025), (0.05), (0.10), (0.25), (0.50), (0.75), (0.90), (0.95), (0.975), (0.99)) p(q)
where b.tested group by p.q order by p.q;

-- 1b. How the classes drew, and where their draw prices sat.
select book, count(*) matches, round(100.0 * avg(drew::int) filter (where draws = 1 and teams = 2), 1) drew_pct,
       round((avg(draw_price) * 100)::numeric, 1) avg_draw_quote_c, count(*) filter (where draw_price >= 0.40) draw_quote_40c_up,
       round((percentile_cont(0.5) within group (order by total) * 100)::numeric, 1) median_total_c
from books where draws = 1 and teams = 2 group by rollup(1) order by 1;

-- Every large-trade alert for a Polymarket buy at 2c to 98c from 2026-04-02 to 2026-09-13 on a sports category,
-- or on a both-teams-to-score market (that study has no category filter). One scan, for every study below.
create temp table wa as
select w.id, w.trader_id, w.condition_id, w.traded_at, w.outcome_index, w.price_num, w.usdc_notional_num, w.category
from whale_alerts w
where w.platform = 'polymarket' and w.side = 0
  and w.traded_at >= date '2026-04-02' and w.traded_at < date '2026-09-14'
  and w.price_num between 0.02 and 0.98
  and (w.category in ('Soccer','NBA','Esports','Tennis','Baseball','Hockey','Basketball','Cricket',
                      'MMA','NFL','Golf','WNBA','Formula 1','Boxing','NCAAF','NCAAB','Table Tennis',
                      'NBA Summer League','CFL','Sports','Big Game','Pickleball')
       or w.condition_id in (select condition_id from markets where sports_market_type = 'both_teams_to_score'));
analyze wa;
create temp table wam as
select wa.*, mo.winning_outcome wo, mo.resolved_at, m.event_slug, m.sports_market_type mtype, m.game_start_time ko,
       m.outcome_yes, m.outcome_no, m.line, regexp_replace(m.event_slug, '-(more-markets|halftime-result)$', '') match_slug
from wa join market_outcomes mo on mo.condition_id = wa.condition_id
left join markets m on m.condition_id = wa.condition_id
where mo.resolved_at > wa.traded_at;
alter table wam add column off_book boolean;
update wam set off_book = coalesce(match_slug in (select event_slug from books where book = 'off'), false);
analyze wam;

-- The draws study's buys (its query 4 universe), with the match's class.
create temp table buys as
select w.id, w.trader_id, w.condition_id, w.traded_at, w.outcome_index, w.price_num, w.usdc_notional_num,
       l.leg, l.event_slug, l.game_start_time, b.book, b.total,
       case when w.outcome_index = 0 then 'Yes' else 'No' end side,
       case when w.traded_at < l.game_start_time then 'pre-kickoff' else 'in-play' end phase,
       (w.outcome_index = l.winning_outcome)::int won
from wam w
join legs l on l.condition_id = w.condition_id
join books b on b.event_slug = l.event_slug
where w.category = 'Soccer';
create temp table u as
select 'all'::text universe, * from buys
union all
select 'kept', * from buys where book <> 'off';
analyze u;

-- 2. The sample, against the study's query 4 (92,313 buys, 5,903 wallets, 4,763 markets, $1.95 billion,
--    10,724 draw buys, 32,910 in-play buys), and what the filter drops.
select universe, count(*) buys, count(distinct trader_id) wallets, count(distinct condition_id) markets,
       count(distinct event_slug) matches, round(sum(usdc_notional_num)/1e6, 1) notional_musd,
       count(*) filter (where leg = 'draw') draw_buys, count(*) filter (where phase = 'in-play') in_play_buys,
       count(*) filter (where leg = 'draw' and side = 'Yes' and phase = 'pre-kickoff') prekick_draw_yes_buys,
       count(distinct condition_id) filter (where leg = 'draw' and side = 'Yes' and phase = 'pre-kickoff') prekick_draw_yes_markets
from u group by 1 order by 1;
select book, count(*) buys, count(distinct event_slug) matches,
       count(*) filter (where leg = 'draw' and side = 'Yes' and phase = 'pre-kickoff') prekick_draw_yes_buys,
       count(distinct condition_id) filter (where leg = 'draw' and side = 'Yes' and phase = 'pre-kickoff') prekick_draw_yes_markets
from buys group by rollup(1) order by 1;

-- 3. Leg x side, every phase and each phase (the study's queries 5 and 6).
select universe, coalesce(phase, 'all phases') phase, leg, side, count(*) buys, count(distinct condition_id) markets,
       round(sum(usdc_notional_num)/1e6, 1) notional_musd, round(avg(price_num)*100, 1) avg_price_c, round(avg(won)::numeric*100, 1) win_pct,
       round((avg(won)::numeric - avg(price_num))*100, 2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100, 2) dollar_roi_pct
from u group by grouping sets ((universe, leg, side), (universe, phase, leg, side)) order by 1, 2, 3, 4;

-- 4. Pre-kickoff draw Yes by price band, per buy (the study's query 7).
select universe, case when price_num < 0.20 then 'a. under 20c' when price_num < 0.25 then 'b. 20-25c' when price_num < 0.30 then 'c. 25-30c'
                      when price_num < 0.35 then 'd. 30-35c' else 'e. 35c+' end band,
       count(*) buys, count(distinct condition_id) markets, round(avg(price_num)*100, 1) avg_price_c, round(avg(won)::numeric*100, 1) win_pct,
       round((avg(won)::numeric - avg(price_num))*100, 2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100, 2) dollar_roi_pct
from u where phase = 'pre-kickoff' and leg = 'draw' and side = 'Yes' group by 1, 2 order by 1, 2;

-- 5. Pre-kickoff draw Yes with each match counted once (the study's query 8), then by the match's average price
--    paid, with binomial half-widths on the draw rate: the draw-price calibration by band.
with pm as (select universe, condition_id, avg(price_num) p, max(won) drew from u where phase = 'pre-kickoff' and leg = 'draw' and side = 'Yes' group by 1, 2)
select universe, count(*) markets, round(avg(p)*100, 1) avg_price_c, round(avg(drew)::numeric*100, 1) draw_pct,
       round((avg(drew)::numeric - avg(p))*100, 2) edge_pts,
       round(100 * 1.959964 * sqrt(avg(drew)::numeric * (1 - avg(drew)::numeric) / count(*)), 2) half_width_pts
from pm group by 1 order by 1;
with pm as (select universe, condition_id, avg(price_num) p, max(won) drew from u where phase = 'pre-kickoff' and leg = 'draw' and side = 'Yes' group by 1, 2)
select universe, case when p < 0.20 then 'a. under 20c' when p < 0.25 then 'b. 20-25c' when p < 0.30 then 'c. 25-30c'
                      when p < 0.35 then 'd. 30-35c' else 'e. 35c+' end band,
       count(*) markets, round(avg(p)*100, 1) avg_price_c, round(avg(drew)::numeric*100, 1) draw_pct,
       round((avg(drew)::numeric - avg(p))*100, 2) edge_pts,
       round(100 * 1.959964 * sqrt(avg(drew)::numeric * (1 - avg(drew)::numeric) / count(*)), 2) half_width_pts
from pm group by 1, 2 order by 1, 2;

-- 5b. The matches the filter drops from the pre-kickoff draw Yes buys: their book, price paid and result.
select b.event_slug, round((b.total*100)::numeric, 1) total_c, round((b.draw_price*100)::numeric, 1) draw_quote_c,
       count(*) buys, round(avg(x.price_num)*100, 1) avg_paid_c, max(x.won) drew
from buys x join books b using (event_slug)
where x.book = 'off' and x.phase = 'pre-kickoff' and x.leg = 'draw' and x.side = 'Yes'
group by 1, 2, 3 order by 1;

-- 6. Pre-kickoff team legs, favorite against underdog (the study's query 9).
select universe, case when (side = 'Yes' and price_num >= 0.5) or (side = 'No' and price_num < 0.5) then 'a. favorite leg' else 'b. underdog leg' end leg_kind,
       side, count(*) buys, count(distinct condition_id) markets, round(avg(price_num)*100, 1) avg_price_c, round(avg(won)::numeric*100, 1) win_pct,
       round((avg(won)::numeric - avg(price_num))*100, 2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100, 2) dollar_roi_pct
from u where phase = 'pre-kickoff' and leg = 'team' group by 1, 2, 3 order by 1, 2, 3;

-- 7. In-play draw Yes by price band (the study's query 10).
select universe, case when price_num < 0.30 then 'a. under 30c' when price_num < 0.50 then 'b. 30-50c' when price_num < 0.70 then 'c. 50-70c' else 'd. 70c+' end band,
       count(*) buys, count(distinct condition_id) markets, round(avg(price_num)*100, 1) avg_price_c, round(avg(won)::numeric*100, 1) win_pct,
       round((avg(won)::numeric - avg(price_num))*100, 2) edge_pts
from u where phase = 'in-play' and leg = 'draw' and side = 'Yes' group by 1, 2 order by 1, 2;

-- 8. Month x draw side (the study's query 12), and the concentration of draw Yes buys (its query 13).
select universe, date_trunc('month', traded_at)::date mo, side, count(*) buys, round(avg(price_num)*100, 1) avg_price_c,
       round((avg(won)::numeric - avg(price_num))*100, 2) edge_pts
from u where leg = 'draw' group by 1, 2, 3 order by 1, 2, 3;
with t as (select universe, condition_id, count(*) n, max(won) drew from u where leg = 'draw' and side = 'Yes' group by 1, 2),
r as (select *, row_number() over (partition by universe order by n desc) rk, sum(n) over (partition by universe) tot from t)
select universe, count(*) markets, max(tot) buys, sum(n) filter (where rk <= 10) top10_buys,
       round(100.0 * sum(n) filter (where rk <= 10) / max(tot), 1) top10_share_pct, sum(drew) filter (where rk <= 10) top10_drew
from r group by 1 order by 1;

-- 9. Sensitivity to the tolerance: the pre-kickoff draw, per buy and per match, and pre-kickoff team No, with the
--    OFF matches defined at 2c, 3c, 5c (the filter above) and 10c, and with every untested match dropped too.
with tol(name, lo, hi, drop_untested) as (values ('a. none', -1.0, 9.0, false), ('b. 10c', 0.90, 1.10, false), ('c. 5c', 0.95, 1.05, false),
                                         ('d. 3c', 0.97, 1.03, false), ('e. 2c', 0.98, 1.02, false), ('f. 5c, tested only', 0.95, 1.05, true)),
x as (select t.name, b.* from tol t join buys b on (b.book = 'untested' and not t.drop_untested) or (b.book <> 'untested' and b.total between t.lo and t.hi)),
pm as (select name, condition_id, avg(price_num) p, max(won) drew from x where phase = 'pre-kickoff' and leg = 'draw' and side = 'Yes' group by 1, 2)
select x.name, count(distinct x.event_slug) matches,
       count(*) filter (where phase = 'pre-kickoff' and leg = 'draw' and side = 'Yes') draw_yes_buys,
       round(((avg(won) filter (where phase = 'pre-kickoff' and leg = 'draw' and side = 'Yes'))::numeric
             - avg(price_num) filter (where phase = 'pre-kickoff' and leg = 'draw' and side = 'Yes')) * 100, 2) draw_yes_edge_pts,
       (select count(*) from pm where pm.name = x.name) draw_markets,
       (select round(avg(p)*100, 1) from pm where pm.name = x.name) draw_market_price_c,
       (select round(avg(drew)::numeric*100, 1) from pm where pm.name = x.name) draw_market_drew_pct,
       round(((avg(won) filter (where phase = 'pre-kickoff' and leg = 'team' and side = 'No'))::numeric
             - avg(price_num) filter (where phase = 'pre-kickoff' and leg = 'team' and side = 'No')) * 100, 2) team_no_edge_pts
from x group by 1 order by 1;

-- 10. Market-level export for the clustered bootstrap: the study's groups (its query 14, less the grade cohorts,
--     which the October 7 grade-at-trade run owns), each prefixed with the universe.
\copy (select grp, condition_id, count(*) n, sum(won::numeric - price_num) sum_edge from (select universe || ' ' || leg || ' ' || side grp, condition_id, won, price_num from u union all select universe || ' ' || phase || ' ' || leg || ' ' || side, condition_id, won, price_num from u union all select universe || ' pre-kickoff draw Yes ' || case when price_num < 0.25 then 'under 25c' when price_num < 0.30 then '25-30c' else '30c+' end, condition_id, won, price_num from u where phase = 'pre-kickoff' and leg = 'draw' and side = 'Yes') x group by 1, 2 order by 1, 2) to './2026-10-11-soccer-draws-price-sum-filter-market-edge.csv' with (format csv, header true)

-- 11. The other studies' soccer rows, all against kept. Each block follows the study's own universe.
-- 11a. Both teams to score, query 9: buys on both-teams-to-score markets with a kickoff before 2026-09-14.
select case when grouping(off_book) = 1 then 'all' else 'kept' end universe,
       case when outcome_index = 0 then 'Yes' else 'No' end side, count(*) buys, count(distinct condition_id) markets,
       round(avg(price_num)*100, 1) avg_price_c, round(avg((outcome_index = wo)::int)::numeric*100, 1) win_pct,
       round((avg((outcome_index = wo)::int)::numeric - avg(price_num))*100, 2) edge_pts
from wam
where mtype = 'both_teams_to_score' and outcome_yes = 'Yes' and outcome_no = 'No' and ko is not null and ko < timestamptz '2026-09-14'
  and wo in (0, 1)
group by grouping sets ((outcome_index), (outcome_index, off_book))
having grouping(off_book) = 1 or off_book is false
order by 1, 2 desc;
-- 11b. Over/under, queries 4 and 7: soccer game totals, by side, and by line for 1.5, 2.5 and 3.5 goals.
select case when grouping(off_book) = 1 then 'all' else 'kept' end universe, coalesce(line::text, 'every line') line,
       case when outcome_index = 0 then 'Over' else 'Under' end side, count(*) buys, count(distinct condition_id) markets,
       round(avg(price_num)*100, 1) avg_price_c, round((avg((outcome_index = wo)::int)::numeric - avg(price_num))*100, 2) edge_pts
from wam
where category = 'Soccer' and mtype = 'totals' and outcome_yes = 'Over' and outcome_no = 'Under' and wo in (0, 1)
group by grouping sets ((outcome_index), (outcome_index, off_book), (line, outcome_index), (line, outcome_index, off_book))
having (grouping(off_book) = 1 or off_book is false) and (grouping(line) = 1 or line in (1.5, 2.5, 3.5))
order by 2, 1, 3;
-- 11c. Favorite-longshot, queries 4 and 5: every soccer buy (trades before 2026-09-12, any market type), and the
--      buys at 70c and up; then the pooled 10c buckets of query 2 across all 22 sports, with soccer's OFF matches out.
select case when grouping(off_book) = 1 then 'all' else 'kept' end universe, case when c then 'all prices' else '70c+' end cut,
       count(*) buys, count(distinct condition_id) markets, round(avg(price_num)*100, 1) avg_price_c,
       round((avg((outcome_index = wo)::int)::numeric - avg(price_num))*100, 2) edge_pts
from (select *, true c from wam where category = 'Soccer' and traded_at < date '2026-09-12' and wo in (0, 1)
      union all select *, false from wam where category = 'Soccer' and traded_at < date '2026-09-12' and wo in (0, 1) and price_num >= 0.70) s
group by grouping sets ((c), (c, off_book)) having grouping(off_book) = 1 or off_book is false
order by 2, 1;
select width_bucket(price_num, 0, 1, 10) b, count(*) buys, count(*) filter (where off_book) off_soccer_buys,
       round((avg((outcome_index = wo)::int)::numeric - avg(price_num))*100, 2) all_edge_pts,
       round(((avg((outcome_index = wo)::int) filter (where not off_book))::numeric - avg(price_num) filter (where not off_book))*100, 2) kept_edge_pts
from wam
where category in ('Soccer','NBA','Esports','Tennis','Baseball','Hockey','Basketball','Cricket','MMA','NFL','Golf','WNBA','Formula 1','Boxing',
                   'NCAAF','NCAAB','Table Tennis','NBA Summer League','CFL','Sports','Big Game','Pickleball')
  and traded_at < date '2026-09-12' and wo in (0, 1)
group by 1 order by 1;
-- 11d. Fading the crowd, section 4 of 2026-10-07-sports-grade-at-trade.sql, soccer only: pre-kickoff buys from
--      2026-06-01 to 2026-09-12 on moneyline, child moneyline, spread, total or untyped markets, graded as the wallet
--      stood at the trade; the D and F crowd side on markets with $5,000 or more of D and F money from two or more
--      D and F buys, leaning 90% or more one way (FADE_BY_SPORT's soccer row: 477 markets, 74.1c, 71.3%, -2.86).
create temp table fb as
select w.trader_id, w.condition_id, w.outcome_index, w.price_num::float8 price_num, w.usdc_notional_num::float8 usd, w.wo, w.off_book,
       case when g.grade in ('S','A','B') then 'sab' when g.grade in ('D','F') then 'df' else 'other' end cohort
from wam w
left join lateral (select tr.grade from trader_rankings tr
                   where tr.trader_id = w.trader_id and tr.date <= w.traded_at::date and tr.computed_at <= w.traded_at
                   order by tr.date desc limit 1) g on true
where w.category = 'Soccer' and w.traded_at >= timestamptz '2026-06-01' and w.traded_at < timestamptz '2026-09-13'
  and (w.mtype in ('moneyline','child_moneyline','spreads','totals') or w.mtype is null)
  and w.ko is not null and w.traded_at < w.ko and w.wo in (0, 1);
with fmk as (
  select condition_id, max(wo) wo, bool_or(off_book) off_book,
         sum(usd) filter (where cohort = 'df' and outcome_index = 0) df0, sum(usd) filter (where cohort = 'df' and outcome_index = 1) df1,
         count(*) filter (where cohort = 'df') n_df,
         avg(price_num) filter (where cohort = 'df' and outcome_index = 0) dfp0, avg(price_num) filter (where cohort = 'df' and outcome_index = 1) dfp1
  from fb group by 1),
fd as (
  select *, case when coalesce(df0,0) >= coalesce(df1,0) then 0 else 1 end side,
         case when coalesce(df0,0) >= coalesce(df1,0) then dfp0 else dfp1 end side_price,
         greatest(coalesce(df0,0),coalesce(df1,0))/(coalesce(df0,0)+coalesce(df1,0)) lean
  from fmk where coalesce(df0,0)+coalesce(df1,0) >= 5000 and n_df >= 2)
select case when grouping(off_book) = 1 then 'all' else 'kept' end universe, count(*) markets, count(*) filter (where off_book) off_markets,
       round((avg(side_price)*100)::numeric, 1) price, round((100.0*avg((side = wo)::int))::numeric, 1) won,
       round(((avg((side = wo)::int) - avg(side_price))*100)::numeric, 2) edge,
       round(sum((side = wo)::int - side_price)::numeric * 100, 1) sum_edge_pts
from fd where lean >= 0.9
group by grouping sets ((), (off_book)) having grouping(off_book) = 1 or off_book is false
order by 1;
