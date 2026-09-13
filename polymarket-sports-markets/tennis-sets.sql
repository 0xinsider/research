-- Study 10: the first set in Polymarket tennis. How often does the first-set winner win the match?
-- Read-only. Read-only role against production.  psql "$DATABASE_URL" -X -f tennis-sets.sql
-- Market results only (no alert-table rows), so no April 2 boundary. A tennis match on Polymarket is an event with
-- a match market (outcomes are full player names) and set markets, "Set 1 Winner: <A> vs <B>" and
-- "Set N Winner: ..." (outcomes are surnames). A set outcome is mapped to a match outcome when the match
-- outcome equals the set outcome or ends with " <set outcome>"; doubles (names with "/") and matches whose two
-- players share a last name are excluded. Temp tables so each scan runs once.
select now() as run_at;

create temp table ev as
select m.event_slug, split_part(m.event_slug, '-', 1) tour, m.title ml_title, m.outcome_yes ml0, m.outcome_no ml1,
       mo.winning_outcome mw, m.game_start_time
from markets m join market_outcomes mo on mo.condition_id = m.condition_id
where m.category = 'Tennis' and m.sports_market_type = 'moneyline' and m.outcome_yes <> '' and m.outcome_no <> ''
  and m.outcome_yes not like '%/%' and m.outcome_no not like '%/%'
  and split_part(reverse(m.outcome_yes), ' ', 1) <> split_part(reverse(m.outcome_no), ' ', 1)
  and mo.winning_outcome in (0, 1) and m.game_start_time is not null and m.game_start_time < timestamptz '2026-09-14';

create temp table set_mk as
select m.event_slug, m.sports_market_type, m.title, m.outcome_yes s0, m.outcome_no s1, mo.winning_outcome sw,
       case when m.sports_market_type = 'tennis_first_set_winner' then 1
            else substring(m.title from '^Set ([1-5]) Winner:')::int end set_no
from markets m join market_outcomes mo on mo.condition_id = m.condition_id
where m.sports_market_type in ('tennis_first_set_winner', 'tennis_set_winner') and m.outcome_yes <> '' and m.outcome_no <> ''
  and mo.winning_outcome in (0, 1) and m.event_slug in (select event_slug from ev);

-- Set winner expressed as the match outcome index (0 or 1); null when the names do not map.
create temp table sets as
select e.event_slug, e.tour, e.mw, s.set_no,
       case when (e.ml0 = s.s0 or e.ml0 like '% ' || s.s0) and (e.ml1 = s.s1 or e.ml1 like '% ' || s.s1) then s.sw
            when (e.ml0 = s.s1 or e.ml0 like '% ' || s.s1) and (e.ml1 = s.s0 or e.ml1 like '% ' || s.s0) then 1 - s.sw end set_w
from ev e join set_mk s using (event_slug)
where s.set_no between 1 and 5;

-- Format: best of five when the event lists a market only a best-of-five match carries: a Set 4 or Set 5 winner
-- market, a -2.5 set handicap, a Total Sets O/U 3.5 or 4.5 line, or a match games total of 30 or more. A tournament
-- title is not a format flag: Polymarket files Australian Open qualifying under "Australian Open Men's" (query 7).
create temp table fmt as
select e.event_slug,
       coalesce(bool_or(m.title ~ '^Set [45] Winner:'
                        or (m.sports_market_type = 'tennis_set_handicap' and m.title like '%(-2.5)%')
                        or (m.sports_market_type = 'tennis_set_totals' and m.title ~ 'Total Sets O/U [34][.]5$')
                        or (m.sports_market_type = 'tennis_match_totals' and substring(m.title from 'Match O/U ([0-9.]+)$')::numeric >= 30)), false) best_of_5
from ev e left join markets m on m.event_slug = e.event_slug
  and m.sports_market_type in ('tennis_set_winner', 'tennis_set_handicap', 'tennis_set_totals', 'tennis_match_totals')
group by 1;

-- One row per match with its set results pivoted.
create temp table mt as
select e.event_slug, e.tour, e.mw, e.ml_title, e.game_start_time, f.best_of_5,
       max(s.set_w) filter (where s.set_no = 1) s1w, max(s.set_w) filter (where s.set_no = 2) s2w,
       max(s.set_w) filter (where s.set_no = 3) s3w,
       count(*) filter (where s.set_no = 1 and s.set_w is null) s1_unmapped
from ev e join sets s using (event_slug) join fmt f using (event_slug)
group by 1,2,3,4,5,6;

-- 1. Sample: matches, name mapping, and the format flag.
select count(*) matches_with_set_markets, count(*) filter (where s1w is not null) with_set1_mapped,
       count(*) filter (where s1_unmapped > 0) set1_unmapped,
       count(*) filter (where best_of_5) best_of_5, count(*) filter (where best_of_5 and s1w is not null) best_of_5_with_set1,
       min(game_start_time)::date first_match, max(game_start_time)::date last_match
from mt;

-- 2. The first-set winner won the match: all, with a binomial half-width.
select count(*) matches, round(100.0*avg((s1w = mw)::int), 1) set1_winner_won_pct,
       round(100*1.959964*sqrt(avg((s1w = mw)::int)::numeric*(1-avg((s1w = mw)::int)::numeric)/count(*)), 2) half_width_pts
from mt where s1w is not null;

-- 3. By tour prefix and format.
select tour, case when best_of_5 then 'best of 5' else 'best of 3' end fmt, count(*) matches,
       round(100.0*avg((s1w = mw)::int), 1) set1_winner_won_pct,
       round(100*1.959964*sqrt(avg((s1w = mw)::int)::numeric*(1-avg((s1w = mw)::int)::numeric)/count(*)), 2) half_width_pts,
       (array_agg(ml_title order by game_start_time desc))[1] latest_match
from mt where s1w is not null group by rollup(1, 2) having count(*) >= 100 order by 1, 2;

-- 4. Best of three with sets 1 and 2 on record: straight sets, deciders, and who wins the decider.
select count(*) matches,
       round(100.0*avg((s1w = s2w)::int), 1) same_player_won_sets_1_and_2_pct,
       round(100*1.959964*sqrt(avg((s1w = s2w)::int)::numeric*(1-avg((s1w = s2w)::int)::numeric)/count(*)), 2) straight_sets_half_width_pts,
       round(100.0*avg((s1w = s2w and mw = s1w)::int) / nullif(avg((s1w = s2w)::int), 0), 1) of_those_won_match_pct,
       count(*) filter (where s1w <> s2w) went_to_decider,
       round(100.0*avg((mw = s1w)::int) filter (where s1w <> s2w), 1) set1_winner_won_decider_match_pct,
       round(100*1.959964*sqrt((avg((mw = s1w)::int) filter (where s1w <> s2w))::numeric*(1-(avg((mw = s1w)::int) filter (where s1w <> s2w))::numeric)/(count(*) filter (where s1w <> s2w))), 2) decider_half_width_pts,
       count(*) filter (where s1w <> s2w and s3w is not null) decider_with_set3_market,
       round(100.0*avg((s3w = mw)::int) filter (where s1w <> s2w and s3w is not null), 1) set3_winner_won_match_pct
from mt where not best_of_5 and s1w is not null and s2w is not null;

-- 5. Best of five with sets 1 and 2 on record.
select count(*) matches, round(100.0*avg((s1w = mw)::int), 1) set1_winner_won_pct,
       round(100.0*avg((mw = s1w)::int) filter (where s1w = s2w), 1) won_sets_1_and_2_then_match_pct,
       count(*) filter (where s1w = s2w) won_first_two,
       round(100.0*avg((mw = s1w)::int) filter (where s1w <> s2w), 1) split_first_two_set1_winner_won_pct,
       count(*) filter (where s1w <> s2w) split_first_two
from mt where best_of_5 and s1w is not null and s2w is not null;

-- 6. By calendar quarter of the match.
select date_trunc('quarter', game_start_time)::date quarter, count(*) matches, round(100.0*avg((s1w = mw)::int), 1) set1_winner_won_pct
from mt where s1w is not null group by 1 order by 1;

-- 7. The check on the format flag: the tournaments behind every best-of-five match, with their dates; and the
-- Australian Open men's title split by the flag and by day, which separates qualifying (January 11 to 15 UTC) from
-- the main draw.
select split_part(ml_title, ':', 1) tournament, count(*) matches, min(game_start_time)::date first_match, max(game_start_time)::date last_match
from mt where best_of_5 and s1w is not null group by 1 order by 2 desc;
select best_of_5, min(game_start_time)::date first_match, max(game_start_time)::date last_match, count(*) matches
from mt where ml_title like 'Australian Open Men''s:%' and s1w is not null
group by 1, (game_start_time < timestamptz '2026-01-16') order by 2;

-- 8. Total Sets O/U markets on the same singles matches: how often the match went the distance. Outcome 0 is Over.
-- O/U 2.5 in a best-of-three match settles Over when it goes to a third set; O/U 3.5 in a best-of-five settles Over
-- at four or five sets.
create temp table set_totals as
select m.event_slug, e.tour, substring(m.title from 'Total Sets O/U ([0-9.]+)$') line, mo.winning_outcome w
from markets m join market_outcomes mo on mo.condition_id = m.condition_id join ev e on e.event_slug = m.event_slug
where m.sports_market_type = 'tennis_set_totals' and m.outcome_yes like 'Over %' and mo.winning_outcome in (0, 1);
select s.line, case when f.best_of_5 then 'best of 5' else 'best of 3' end fmt, count(*) markets,
       round(100.0*avg((s.w = 0)::int), 1) over_pct,
       round(100*1.959964*sqrt(avg((s.w = 0)::int)::numeric*(1-avg((s.w = 0)::int)::numeric)/count(*)), 2) half_width_pts
from set_totals s join fmt f using (event_slug) group by 1, 2 order by 1, 2;
select s.tour, count(*) markets, round(100.0*avg((s.w = 0)::int), 1) over_pct,
       round(100*1.959964*sqrt(avg((s.w = 0)::int)::numeric*(1-avg((s.w = 0)::int)::numeric)/count(*)), 2) half_width_pts
from set_totals s join fmt f using (event_slug) where s.line = '2.5' and not f.best_of_5 group by rollup(1) order by 1;

-- 9. Cross-check: on best-of-three matches with Set 1 and Set 2 markets and an O/U 2.5 total, a split of the first
-- two sets should match an Over.
select count(*) matches, round(100.0*avg(((m.s1w <> m.s2w) = (s.w = 0))::int), 1) agreement_pct
from mt m join set_totals s using (event_slug)
where not m.best_of_5 and m.s1w is not null and m.s2w is not null and s.line = '2.5';
