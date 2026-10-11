-- #23731 (epic #23652). The tennis first-set study (2026-09-13-sports-tennis-sets.sql.txt) re-run on the data as it
-- stands on 2026-10-11: the published window plus a dated extension, with the tour split kept beside every rate.
--
-- WHY. Slice R4 (#23679, 2026-10-11-tennis-first-set-winner-polymarket-charts.sql.txt) rebuilt the study's window
-- (matches starting before 2026-09-14) and found 20,777 matches with a mapped first set where the September 13 run
-- held 12,640, at 82.3% against 80.7%. 0xinsider has since recorded settled set markets for thousands more matches,
-- most of them on the ITF tour, where the first set decides more. markets.created_at is null on most tennis rows,
-- so the September universe cannot be cut back out: this run replaces it, and keeps the tour mix visible so a
-- change in the mix cannot pass as a trend.
--
-- RULES. The study's, unchanged: singles match markets settled to a player (outcome 0 or 1), set markets mapped
-- to the match by surname, doubles and shared surnames out, 50-50 settlements out, the same best-of-five flag.
-- Tennis markets are found by event slug prefix (atp-, wta-, itf-) and category 'Tennis', as R4 read them.
-- WINDOWS. 'a. published': matches starting before 2026-09-14, the study's window (first match 2025-11-09).
-- 'b. extension': 2026-09-14 to 2026-10-10. 'c. all': both, the current reading.
--
-- WHERE IT RAN. On a Neon child branch of production (claude-18-23731-reruns, forked 14:56 UTC on 2026-10-11,
-- deleted after the runs) through ./scripts/neon-child-branch.sh query, read-only against production; the temp
-- tables live only in the session. Output: 2026-10-11-sports-tennis-sets-rerun-output.txt beside this file.
select now() as run_at;

create temp table tm0 as
select m.condition_id, m.event_slug, split_part(m.event_slug, '-', 1) tour, m.sports_market_type, m.title,
       m.outcome_yes, m.outcome_no, m.game_start_time
from markets m
where (m.event_slug like 'atp-%' or m.event_slug like 'wta-%' or m.event_slug like 'itf-%') and m.category = 'Tennis';
analyze tm0;
set enable_nestloop = off;
create temp table tmo as
select mo.condition_id, mo.winning_outcome from market_outcomes mo where mo.condition_id in (select condition_id from tm0);
reset enable_nestloop;
create temp table tm as
select t.*, o.winning_outcome w from tm0 t left join tmo o using (condition_id);
analyze tm;

create temp table ev as
select event_slug, tour, title ml_title, outcome_yes ml0, outcome_no ml1, w mw, game_start_time
from tm
where sports_market_type = 'moneyline' and outcome_yes <> '' and outcome_no <> ''
  and outcome_yes not like '%/%' and outcome_no not like '%/%'
  and split_part(reverse(outcome_yes), ' ', 1) <> split_part(reverse(outcome_no), ' ', 1)
  and w in (0, 1) and game_start_time is not null and game_start_time < timestamptz '2026-10-11';

create temp table sets as
select e.event_slug, s.set_no,
       case when (e.ml0 = s.s0 or e.ml0 like '% ' || s.s0) and (e.ml1 = s.s1 or e.ml1 like '% ' || s.s1) then s.sw
            when (e.ml0 = s.s1 or e.ml0 like '% ' || s.s1) and (e.ml1 = s.s0 or e.ml1 like '% ' || s.s0) then 1 - s.sw end set_w
from ev e join (
  select event_slug, outcome_yes s0, outcome_no s1, w sw,
         case when sports_market_type = 'tennis_first_set_winner' then 1 else substring(title from '^Set ([1-5]) Winner:')::int end set_no
  from tm where sports_market_type in ('tennis_first_set_winner', 'tennis_set_winner') and outcome_yes <> '' and outcome_no <> '' and w in (0, 1)
) s using (event_slug)
where s.set_no between 1 and 5;

create temp table fmt as
select e.event_slug,
       coalesce(bool_or(t.title ~ '^Set [45] Winner:'
                        or (t.sports_market_type = 'tennis_set_handicap' and t.title like '%(-2.5)%')
                        or (t.sports_market_type = 'tennis_set_totals' and t.title ~ 'Total Sets O/U [34][.]5$')
                        or (t.sports_market_type = 'tennis_match_totals' and substring(t.title from 'Match O/U ([0-9.]+)$')::numeric >= 30)), false) best_of_5
from ev e left join tm t on t.event_slug = e.event_slug
  and t.sports_market_type in ('tennis_set_winner', 'tennis_set_handicap', 'tennis_set_totals', 'tennis_match_totals')
group by 1;

create temp table mt as
select e.event_slug, e.tour, e.mw, e.ml_title, e.game_start_time, f.best_of_5,
       max(s.set_w) filter (where s.set_no = 1) s1w, max(s.set_w) filter (where s.set_no = 2) s2w,
       max(s.set_w) filter (where s.set_no = 3) s3w,
       count(*) filter (where s.set_no = 1 and s.set_w is null) s1_unmapped,
       case when e.game_start_time < timestamptz '2026-09-14' then 'a. published' else 'b. extension' end win,
       case when e.tour = 'itf' then 'ITF' else 'ATP and WTA' end tour_group,
       case when e.tour = 'atp' and f.best_of_5 then 'atp5' when e.tour = 'atp' then 'atp3' else e.tour end tour_fmt
from ev e join sets s using (event_slug) join fmt f using (event_slug)
group by 1,2,3,4,5,6;
create temp table mw as
select *, win w2 from mt union all select *, 'c. all' from mt;
analyze mw;

-- 1. Sample by window: singles match markets, matches with a settled set market, with a mapped first set.
select w2 win, count(*) matches_with_set_markets, count(*) filter (where s1w is not null) with_set1_mapped,
       count(*) filter (where s1_unmapped > 0) set1_unmapped, count(*) filter (where best_of_5 and s1w is not null) best_of_5_with_set1,
       min(game_start_time)::date first_match, max(game_start_time)::date last_match
from mw group by 1 order by 1;
select case when game_start_time < timestamptz '2026-09-14' then 'a. published' else 'b. extension' end win, count(*) singles_match_markets
from ev group by rollup(1) order by 1;

-- 2. The first-set winner won the match, by window, with a binomial half-width.
select w2 win, count(*) matches, round(100.0*avg((s1w = mw)::int), 1) set1_winner_won_pct,
       round(100*1.959964*sqrt(avg((s1w = mw)::int)::numeric*(1-avg((s1w = mw)::int)::numeric)/count(*)), 2) half_width_pts
from mw where s1w is not null group by 1 order by 1;

-- 3. By window, tour and format (the study's query 3), and each window's mix of tours.
select w2 win, tour_fmt, count(*) matches, round(100.0*count(*)/sum(count(*)) over (partition by w2), 1) share_pct,
       round(100.0*avg((s1w = mw)::int), 1) set1_winner_won_pct,
       round(100*1.959964*sqrt(avg((s1w = mw)::int)::numeric*(1-avg((s1w = mw)::int)::numeric)/count(*)), 2) half_width_pts,
       (array_agg(ml_title order by game_start_time desc))[1] latest_match
from mw where s1w is not null group by 1, 2 order by 1, 2;

-- 3b. Mix against rate. Each window's best-of-three rate re-weighted to the published window's mix of the three
--     best-of-three tours (ATP, WTA, ITF; the extension has no best-of-five match): what the extension would read
--     if only the rates had moved, beside the published window on the same weights.
with r as (select win, tour_fmt, count(*) n, avg((s1w = mw)::int::numeric) rate from mt where s1w is not null and tour_fmt <> 'atp5' group by 1, 2),
mix as (select tour_fmt, n::numeric / sum(n) over () share from r where win = 'a. published')
select r.win, round(100 * sum(mix.share * r.rate), 1) at_published_mix_pct,
       round(100 * sum(r.n * r.rate) / sum(r.n), 1) at_own_mix_pct, sum(r.n) matches
from mix join r using (tour_fmt) group by 1 order by 1;

-- 3c. Month by month, ITF against ATP and WTA: matches and the first-set winner's rate.
select date_trunc('month', game_start_time)::date mo, tour_group, count(*) matches,
       round(100.0*avg((s1w = mw)::int), 1) set1_winner_won_pct
from mt where s1w is not null group by 1, 2 order by 1, 2;

-- 4. Best of three with Set 1 and Set 2 on record (the study's query 4), by window: straight sets, deciders, who
--    won the decider, and each set's winner's match rate.
select w2 win, count(*) matches,
       round(100.0*avg((s1w = s2w)::int), 1) straight_sets_pct,
       round(100*1.959964*sqrt(avg((s1w = s2w)::int)::numeric*(1-avg((s1w = s2w)::int)::numeric)/count(*)), 2) straight_sets_half_width_pts,
       round(100.0*avg((s1w = s2w and mw = s1w)::int) / nullif(avg((s1w = s2w)::int), 0), 1) of_those_won_match_pct,
       count(*) filter (where s1w <> s2w) went_to_decider,
       round(100.0*avg((mw = s1w)::int) filter (where s1w <> s2w), 1) set1_winner_won_decider_match_pct,
       round(100*1.959964*sqrt((avg((mw = s1w)::int) filter (where s1w <> s2w))::numeric*(1-(avg((mw = s1w)::int) filter (where s1w <> s2w))::numeric)/(count(*) filter (where s1w <> s2w))), 2) decider_half_width_pts,
       round(100.0*avg((s1w = mw)::int), 1) set1_winner_won_pct,
       round(100.0*avg((s2w = mw)::int), 1) set2_winner_won_pct
from mw where not best_of_5 and s1w is not null and s2w is not null group by 1 order by 1;
select w2 win, tour_group, count(*) matches, round(100.0*avg((s1w <> s2w)::int), 1) decider_pct,
       round(100.0*avg((mw = s1w)::int) filter (where s1w <> s2w), 1) set1_winner_won_decider_match_pct
from mw where not best_of_5 and s1w is not null and s2w is not null group by 1, 2 order by 1, 2;

-- 5. Best of five with Set 1 and Set 2 on record (the study's query 5), by window.
select w2 win, count(*) matches, round(100.0*avg((s1w = mw)::int), 1) set1_winner_won_pct,
       round(100.0*avg((mw = s1w)::int) filter (where s1w = s2w), 1) won_sets_1_and_2_then_match_pct,
       count(*) filter (where s1w = s2w) won_first_two,
       round(100.0*avg((mw = s1w)::int) filter (where s1w <> s2w), 1) split_first_two_set1_winner_won_pct,
       count(*) filter (where s1w <> s2w) split_first_two
from mw where best_of_5 and s1w is not null and s2w is not null group by 1 order by 1;

-- 6. By calendar quarter of the match, with the ITF share (the study's query 6).
select date_trunc('quarter', game_start_time)::date quarter, count(*) matches, round(100.0*avg((s1w = mw)::int), 1) set1_winner_won_pct,
       round(100.0*avg((tour = 'itf')::int), 1) itf_share_pct
from mt where s1w is not null group by 1 order by 1;

-- 7. The tournaments behind every best-of-five match (the study's query 7), whole run.
select split_part(ml_title, ':', 1) tournament, count(*) matches, min(game_start_time)::date first_match, max(game_start_time)::date last_match
from mt where best_of_5 and s1w is not null group by 1 order by 2 desc;

-- 8. Total Sets O/U on the same singles matches (the study's query 8), by window. Outcome 0 is Over.
create temp table set_totals as
select t.event_slug, e.tour, substring(t.title from 'Total Sets O/U ([0-9.]+)$') line, t.w,
       case when e.game_start_time < timestamptz '2026-09-14' then 'a. published' else 'b. extension' end win
from tm t join ev e on e.event_slug = t.event_slug
where t.sports_market_type = 'tennis_set_totals' and t.outcome_yes like 'Over %' and t.w in (0, 1);
select coalesce(s.win, 'c. all') win, s.line, case when f.best_of_5 then 'best of 5' else 'best of 3' end fmt, count(*) markets,
       round(100.0*avg((s.w = 0)::int), 1) over_pct,
       round(100*1.959964*sqrt(avg((s.w = 0)::int)::numeric*(1-avg((s.w = 0)::int)::numeric)/count(*)), 2) half_width_pts
from set_totals s join fmt f using (event_slug)
where s.line in ('2.5', '3.5', '4.5')
group by grouping sets ((s.win, s.line, f.best_of_5), (s.line, f.best_of_5))
having count(*) >= 20 order by 1, 2, 3;
select coalesce(s.win, 'c. all') win, coalesce(s.tour, 'all') tour, count(*) markets, round(100.0*avg((s.w = 0)::int), 1) over_pct,
       round(100*1.959964*sqrt(avg((s.w = 0)::int)::numeric*(1-avg((s.w = 0)::int)::numeric)/count(*)), 2) half_width_pts
from set_totals s join fmt f using (event_slug) where s.line = '2.5' and not f.best_of_5
group by grouping sets ((s.win, s.tour), (s.win), (s.tour), ()) order by 1, 2;

-- 9. Cross-check (the study's query 9): on best-of-three matches with Set 1 and Set 2 markets and an O/U 2.5,
--    a split of the first two sets should match an Over. Whole run.
select count(*) matches, round(100.0*avg(((m.s1w <> m.s2w) = (s.w = 0))::int), 1) agreement_pct
from mt m join set_totals s using (event_slug)
where not m.best_of_5 and m.s1w is not null and m.s2w is not null and s.line = '2.5';

-- 10. The first set's score, read off the Set 1 Games O/U 8.5, 9.5 and 10.5 markets (R4's query 4), whole run:
--     how often the first-set winner won the match, and how each tour's first sets were won (best of three).
create temp table g1 as
select event_slug,
       max(case when w = 0 then 1 else 0 end) filter (where line = '8.5') o85, count(*) filter (where line = '8.5') n85,
       max(case when w = 0 then 1 else 0 end) filter (where line = '9.5') o95, count(*) filter (where line = '9.5') n95,
       max(case when w = 0 then 1 else 0 end) filter (where line = '10.5') o105, count(*) filter (where line = '10.5') n105
from (select event_slug, substring(title from 'Set 1 Games O/U ([0-9.]+)$') line, w from tm
      where sports_market_type = 'tennis_first_set_totals' and outcome_yes like 'Over%' and w in (0, 1)) x
group by 1;
create temp table mc as
select m.*, case
    when g.n85 = 1 and g.o85 = 0 and coalesce(g.o95, 0) = 0 and coalesce(g.o105, 0) = 0 then 'a. 6-0, 6-1 or 6-2'
    when g.n85 = 1 and g.n95 = 1 and g.o85 = 1 and g.o95 = 0 and coalesce(g.o105, 0) = 0 then 'b. 6-3'
    when g.n95 = 1 and g.n105 = 1 and g.o95 = 1 and g.o105 = 0 and coalesce(g.o85, 1) = 1 then 'c. 6-4'
    when g.n105 = 1 and g.o105 = 1 and coalesce(g.o95, 1) = 1 and coalesce(g.o85, 1) = 1 then 'd. 7-5 or 7-6'
  end set1_class
from mt m left join g1 g using (event_slug);
select coalesce(set1_class, '(lines missing or inconsistent)') set1_class, count(*) matches,
       round(100.0*avg((s1w = mw)::int), 1) set1_winner_won_pct,
       round(100*1.959964*sqrt(avg((s1w = mw)::int)::numeric*(1-avg((s1w = mw)::int)::numeric)/count(*)), 2) half_width_pts
from mc where s1w is not null group by rollup(1) order by 1;
select tour, set1_class, count(*) matches, round(100.0*count(*)/sum(count(*)) over (partition by tour), 1) share_pct,
       round(100.0*avg((s1w = mw)::int), 1) set1_winner_won_pct
from mc where s1w is not null and not best_of_5 and set1_class is not null group by 1, 2 order by 1, 2;
