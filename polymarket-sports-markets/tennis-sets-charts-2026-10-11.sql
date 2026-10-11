-- #23679 (epic #23652, slice R4): section charts for /research/tennis-first-set-winner-polymarket.
--
-- WHERE IT RAN. On a Neon child branch of production forked at 13:03:53 UTC on 2026-10-11
-- (claude18-23679-charts, deleted after the runs), through
-- ./scripts/neon-child-branch.sh query --name claude18-23679-charts -f <this file>, read-only statements only.
-- The run_at line of the committed -output.txt beside this file is the start of the run.
--
-- The study is tennis-sets.sql. This file re-builds its universe with the same rules
-- (match market and set markets per event, set outcome mapped to the match outcome by surname, doubles and
-- shared surnames out, 50-50 settlements out, the same best-of-five flag) and adds the cuts the section
-- charts need. One change in how it reads: tennis markets are found through their event slug prefix
-- (atp-, wta-, itf-), which the markets table indexes, instead of a scan for category = 'Tennis'; the study's
-- 12,640 matches were all under those three prefixes (its query 3), so the universe is the same.
-- Windows: "study window" is the study's, matches starting before 2026-09-14. "Since" is 2026-09-14 to
-- 2026-10-10, the matches that settled after the study ran.
-- THE STUDY WINDOW HAS GROWN. Rebuilt here, the window holds 20,777 matches with a mapped first set where the
-- September 13 run held 12,640: 0xinsider has since recorded settled set markets for thousands more matches,
-- most of them on the ITF tour (query 2b). markets.created_at is null on most tennis rows, so the September
-- universe cannot be cut back out of this one. Every cut below that is not a re-check reads the rebuilt window
-- and says so; the article's own figures stay the September 13 run's.
select now() as run_at;

-- Tennis markets, then their settlements: two steps, so the settlement lookup is one hash join over
-- market_outcomes rather than 450,000 index probes into a cold child branch.
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

-- Singles match markets settled to a player, as the study builds them.
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

-- Set 1 games totals (Over is outcome 0): O/U 8.5, 9.5 and 10.5 place the first set's game count.
create temp table g1 as
select event_slug,
       max(case when w = 0 then 1 else 0 end) filter (where line = '8.5') o85, count(*) filter (where line = '8.5') n85,
       max(case when w = 0 then 1 else 0 end) filter (where line = '9.5') o95, count(*) filter (where line = '9.5') n95,
       max(case when w = 0 then 1 else 0 end) filter (where line = '10.5') o105, count(*) filter (where line = '10.5') n105
from (select event_slug, substring(title from 'Set 1 Games O/U ([0-9.]+)$') line, w from tm
      where sports_market_type = 'tennis_first_set_totals' and outcome_yes like 'Over%' and w in (0, 1)) x
group by 1;

create temp table mt as
select e.event_slug, e.tour, e.mw, e.game_start_time, f.best_of_5,
       max(s.set_w) filter (where s.set_no = 1) s1w, max(s.set_w) filter (where s.set_no = 2) s2w,
       (e.game_start_time < timestamptz '2026-09-14') study
from ev e join sets s using (event_slug) join fmt f using (event_slug)
group by 1,2,3,4,5;

-- First-set game count class, where the three lines settle consistently.
create temp table mc as
select m.*, case
    when g.n85 = 1 and g.o85 = 0 and coalesce(g.o95, 0) = 0 and coalesce(g.o105, 0) = 0 then 'a. 6-0, 6-1 or 6-2'
    when g.n85 = 1 and g.n95 = 1 and g.o85 = 1 and g.o95 = 0 and coalesce(g.o105, 0) = 0 then 'b. 6-3'
    when g.n95 = 1 and g.n105 = 1 and g.o95 = 1 and g.o105 = 0 and coalesce(g.o85, 1) = 1 then 'c. 6-4'
    when g.n105 = 1 and g.o105 = 1 and coalesce(g.o95, 1) = 1 and coalesce(g.o85, 1) = 1 then 'd. 7-5 or 7-6'
  end set1_class,
  case when g.n95 = 1 then g.o95 end set1_over95,
  (g.event_slug is not null) has_set1_games
from mt m left join g1 g using (event_slug);

-- 1. Reproduction: the study window, built again (the study: 28,064 settled singles match markets, 13,222 matches
--    with a settled set market, 12,640 with a mapped first set, 80.7%, half-width 0.69).
select (select count(*) from ev where game_start_time < timestamptz '2026-09-14') singles_match_markets,
       count(*) matches_with_set_markets, count(*) filter (where s1w is not null) with_set1,
       round(100.0*avg((s1w = mw)::int) filter (where s1w is not null), 1) set1_winner_won_pct,
       round(100*1.959964*sqrt((avg((s1w = mw)::int) filter (where s1w is not null))::numeric*(1-(avg((s1w = mw)::int) filter (where s1w is not null))::numeric)/(count(*) filter (where s1w is not null))), 2) half_width_pts
from mt where study;

-- 2. The re-check: matches since the study, and every match to October 10.
select case when study then 'study window' else 'since' end win, count(*) matches,
       round(100.0*avg((s1w = mw)::int), 1) set1_winner_won_pct,
       round(100*1.959964*sqrt(avg((s1w = mw)::int)::numeric*(1-avg((s1w = mw)::int)::numeric)/count(*)), 2) half_width_pts,
       min(game_start_time)::date first_match, max(game_start_time)::date last_match
from mt where s1w is not null group by rollup(1) order by 1;

-- 2b. The study window rebuilt, by tour and format (the study's query 3: ITF 2,235 at 83.1%, WTA 3,844 at 81.1%,
--     ATP best of three 6,039 at 80.0%, ATP best of five 522 at 74.3%).
select tour, case when best_of_5 then 'best of 5' else 'best of 3' end fmt, count(*) matches,
       round(100.0*avg((s1w = mw)::int), 1) set1_winner_won_pct,
       round(100*1.959964*sqrt(avg((s1w = mw)::int)::numeric*(1-avg((s1w = mw)::int)::numeric)/count(*)), 2) half_width_pts
from mt where study and s1w is not null group by 1, 2 order by 1, 2;

-- 3. Best of three with Set 1 and Set 2 on record, study window: how often each set's winner won the match.
select count(*) matches,
       round(100.0*avg((s1w = mw)::int), 1) set1_winner_won_pct,
       round(100*1.959964*sqrt(avg((s1w = mw)::int)::numeric*(1-avg((s1w = mw)::int)::numeric)/count(*)), 2) set1_half_width_pts,
       round(100.0*avg((s2w = mw)::int), 1) set2_winner_won_pct,
       round(100*1.959964*sqrt(avg((s2w = mw)::int)::numeric*(1-avg((s2w = mw)::int)::numeric)/count(*)), 2) set2_half_width_pts,
       round(100.0*avg((s1w <> s2w)::int), 1) third_set_pct,
       round(100*1.959964*sqrt(avg((s1w <> s2w)::int)::numeric*(1-avg((s1w <> s2w)::int)::numeric)/count(*)), 2) third_set_half_width_pts
from mt where study and not best_of_5 and s1w is not null and s2w is not null;

-- 4. The first set's game count, study window: how often its winner won the match.
select coalesce(set1_class, '(lines missing or inconsistent)') set1_class, count(*) matches,
       count(*) filter (where best_of_5) best_of_5,
       round(100.0*avg((s1w = mw)::int), 1) set1_winner_won_pct,
       round(100*1.959964*sqrt(avg((s1w = mw)::int)::numeric*(1-avg((s1w = mw)::int)::numeric)/count(*)), 2) half_width_pts
from mc where study and s1w is not null group by rollup(1) order by 1;
-- The same split on the 9.5 line alone, which more matches carry.
select case set1_over95 when 0 then 'a. 9 games or fewer (6-3 or wider)' when 1 then 'b. 10 or more (6-4, 7-5, 7-6)' else 'c. no settled 9.5 line' end split,
       count(*) matches, round(100.0*avg((s1w = mw)::int), 1) set1_winner_won_pct,
       round(100*1.959964*sqrt(avg((s1w = mw)::int)::numeric*(1-avg((s1w = mw)::int)::numeric)/count(*)), 2) half_width_pts
from mc where study and s1w is not null group by 1 order by 1;
-- By tour (best of three): the share of first sets in each class, and the first-set winner's rate.
select tour, set1_class, count(*) matches, round(100.0*count(*)/sum(count(*)) over (partition by tour), 1) share_pct,
       round(100.0*avg((s1w = mw)::int), 1) set1_winner_won_pct
from mc where study and s1w is not null and not best_of_5 and set1_class is not null group by 1, 2 order by 1, 2;

-- 5. How singles matches with a Completed Match market ended (Yes is outcome 0), to October 10: finished,
--    retired or defaulted after the start (match market paid the player who advanced), or a walkover (match
--    market settled 50-50, -1). Doubles and shared surnames are out, as above; the match market may be void here.
select case when c.w = 0 then 'a. finished' when c.w = 1 and m.w in (0, 1) then 'b. did not finish, match market paid the player who advanced'
            when c.w = 1 and m.w = -1 then 'c. did not finish, match market settled 50-50' else 'd. other' end ending,
       count(*) matches, round(100.0*count(*)/sum(count(*)) over (), 1) share_pct,
       min(m.game_start_time)::date first_match, max(m.game_start_time)::date last_match
from tm c join tm m on m.event_slug = c.event_slug and m.sports_market_type = 'moneyline'
where c.sports_market_type = 'tennis_completed_match' and c.w in (0, 1)
  and m.outcome_yes <> '' and m.outcome_no <> '' and m.outcome_yes not like '%/%' and m.outcome_no not like '%/%'
  and split_part(reverse(m.outcome_yes), ' ', 1) <> split_part(reverse(m.outcome_no), ' ', 1)
  and m.w in (-1, 0, 1) and m.game_start_time < timestamptz '2026-10-11'
group by 1 order by 1;

-- 6. Which market families the study's matches listed (study window, matches with a mapped first set).
create temp table fam as
select event_slug,
       bool_or(sports_market_type = 'tennis_set_totals') total_sets, bool_or(sports_market_type = 'tennis_set_handicap') set_handicap,
       bool_or(sports_market_type = 'tennis_match_totals') total_games, bool_or(sports_market_type = 'tennis_first_set_totals') set1_games,
       bool_or(sports_market_type = 'tennis_set_winner' and title ~ '^Set 2 Winner:') set2_winner,
       bool_or(sports_market_type = 'tennis_completed_match') completed_match
from tm group by 1;
select count(*) matches,
       round(100.0*avg(f.set2_winner::int), 1) set2_winner_pct, round(100.0*avg(f.total_sets::int), 1) total_sets_pct,
       round(100.0*avg(f.set_handicap::int), 1) set_handicap_pct, round(100.0*avg(f.total_games::int), 1) total_games_pct,
       round(100.0*avg(f.set1_games::int), 1) set1_games_pct, round(100.0*avg(f.completed_match::int), 1) completed_match_pct
from mt join fam f using (event_slug) where mt.study and mt.s1w is not null;
