-- Study 9: both teams to score and halftime results on Polymarket soccer.
-- Read-only. Read-only role against production.  psql "$DATABASE_URL" -X -f btts-halftime.sql
-- Outcome counts use every settled market with a kickoff on record; they are market results, which the April 2
-- alert-table defect does not touch. The pricing query uses large-trade alert buys from 2026-04-02.
-- Soccer side markets live under the match's event slug plus a suffix: "-more-markets" for both teams to score
-- and first-half totals, "-halftime-result" for the halftime markets. The three result markets and the game
-- total live under the event slug itself. Joins strip the suffix. Outcome 0 is Yes (or Over) on every market
-- used here. Temp tables, not views, so each market scan runs once.
select now() as run_at;

create temp table btts as
select m.condition_id, regexp_replace(m.event_slug, '-more-markets$', '') base_slug,
       split_part(m.event_slug, '-', 1) league_prefix, m.game_start_time, mo.winning_outcome, m.title
from markets m join market_outcomes mo on mo.condition_id = m.condition_id
where m.sports_market_type = 'both_teams_to_score' and m.outcome_yes = 'Yes' and m.outcome_no = 'No'
  and m.game_start_time is not null and m.game_start_time < timestamptz '2026-09-14' and mo.winning_outcome in (0, 1);

-- 1. Both teams to score: every settled market, with a binomial half-width.
select count(*) markets, round(100.0*count(*) filter (where winning_outcome = 0)/count(*), 1) btts_yes_pct,
       round(100*1.959964*sqrt((count(*) filter (where winning_outcome = 0))::numeric/count(*)*(1-(count(*) filter (where winning_outcome = 0))::numeric/count(*))/count(*)), 2) half_width_pts,
       min(game_start_time)::date first_kickoff, max(game_start_time)::date last_kickoff
from btts;

-- 2. By competition prefix, 250 or more settled markets, with the latest fixture as evidence of the name.
select league_prefix, count(*) markets, round(100.0*count(*) filter (where winning_outcome = 0)/count(*), 1) btts_yes_pct,
       round(100*1.959964*sqrt((count(*) filter (where winning_outcome = 0))::numeric/count(*)*(1-(count(*) filter (where winning_outcome = 0))::numeric/count(*))/count(*)), 2) half_width_pts,
       (array_agg(title order by game_start_time desc))[1] latest_fixture
from btts group by 1 having count(*) >= 250 order by 2 desc;

-- 3. First-half and second-half both teams to score.
select m.sports_market_type, count(*) markets, round(100.0*count(*) filter (where mo.winning_outcome = 0)/count(*), 1) yes_pct
from markets m join market_outcomes mo on mo.condition_id = m.condition_id
where m.sports_market_type in ('both_teams_to_score_first_half', 'both_teams_to_score_second_half') and m.outcome_yes = 'Yes'
  and m.game_start_time is not null and m.game_start_time < timestamptz '2026-09-14' and mo.winning_outcome in (0, 1)
group by 1 order by 1;

-- 4. Both teams to score against the full-match Over/Under 2.5 on the same match.
create temp table over25 as
select regexp_replace(m.event_slug, '-more-markets$', '') base_slug, mo.winning_outcome w
from markets m join market_outcomes mo on mo.condition_id = m.condition_id
where m.category = 'Soccer' and m.sports_market_type = 'totals' and m.line = 2.5 and m.outcome_yes = 'Over' and mo.winning_outcome in (0, 1);
select case when b.winning_outcome = 0 then 'a. both scored' else 'b. not both' end btts, count(*) matches,
       round(100.0*count(*) filter (where o.w = 0)/count(*), 1) over25_pct
from btts b join over25 o using (base_slug) group by rollup(1) order by 1;

-- 5. Both teams to score against the draw (the match's draw market).
create temp table draw_leg as
select m.event_slug base_slug, mo.winning_outcome w
from markets m join market_outcomes mo on mo.condition_id = m.condition_id
where m.category = 'Soccer' and m.sports_market_type = 'moneyline' and m.outcome_yes = 'Yes'
  and (m.group_item_title like 'Draw (%' or m.title like '%end in a draw%') and mo.winning_outcome in (0, 1);
select case when b.winning_outcome = 0 then 'a. both scored' else 'b. not both' end btts, count(*) matches,
       round(100.0*count(*) filter (where d.w = 0)/count(*), 1) draw_pct
from btts b join draw_leg d using (base_slug) group by rollup(1) order by 1;

-- Halftime markets: "<home> vs. <away>: Draw at halftime?" and "<team> leading at halftime?".
create temp table ht as
select m.condition_id, regexp_replace(m.event_slug, '-(more-markets|halftime-result)$', '') base_slug, m.game_start_time, mo.winning_outcome, m.title, m.group_item_title,
       case when m.title like '%: Draw at halftime?' then 'draw' when m.title like '% leading at halftime?' then 'team' else 'other' end kind
from markets m join market_outcomes mo on mo.condition_id = m.condition_id
where m.sports_market_type = 'soccer_halftime_result' and m.outcome_yes = 'Yes' and m.outcome_no = 'No'
  and m.game_start_time is not null and m.game_start_time < timestamptz '2026-09-14' and mo.winning_outcome in (0, 1);

-- 6. Halftime markets: counts and Yes rates.
select kind, count(*) markets, round(100.0*count(*) filter (where winning_outcome = 0)/count(*), 1) yes_pct,
       round(100*1.959964*sqrt((count(*) filter (where winning_outcome = 0))::numeric/count(*)*(1-(count(*) filter (where winning_outcome = 0))::numeric/count(*))/count(*)), 2) half_width_pts,
       (array_agg(title))[1] example
from ht group by 1 order by 1;

-- 7. Level at halftime: how often the match then ends in a draw.
select count(*) matches_level_at_ht, round(100.0*count(*) filter (where d.w = 0)/count(*), 1) ended_draw_pct
from ht h join draw_leg d using (base_slug) where h.kind = 'draw' and h.winning_outcome = 0;

-- 8. Leading at halftime: how often that team wins the match (team-win market on the same event, same team).
create temp table team_win as
select m.event_slug base_slug, m.group_item_title team, mo.winning_outcome w
from markets m join market_outcomes mo on mo.condition_id = m.condition_id
where m.category = 'Soccer' and m.sports_market_type = 'moneyline' and m.outcome_yes = 'Yes'
  and m.group_item_title not like 'Draw (%' and m.title like 'Will % win on %' and mo.winning_outcome in (0, 1);
select count(*) leaders_at_ht,
       round(100.0*count(*) filter (where t.w = 0)/count(*), 1) went_on_to_win_pct,
       round(100.0*count(*) filter (where t.w = 1 and d.w = 0)/count(*), 1) drew_pct,
       round(100.0*count(*) filter (where t.w = 1 and d.w = 1)/count(*), 1) lost_pct
from ht h
join team_win t on t.base_slug = h.base_slug and t.team = h.group_item_title
left join draw_leg d on d.base_slug = h.base_slug
where h.kind = 'team' and h.winning_outcome = 0 and d.w is not null;

-- 9. Large buys on both teams to score, from April 2, 2026.
create temp table bb as
select w.id, w.condition_id, w.traded_at, w.price_num, w.usdc_notional_num, case when w.outcome_index = 0 then 'Yes' else 'No' end side,
       (w.outcome_index = b.winning_outcome)::int won
from whale_alerts w join btts b on b.condition_id = w.condition_id join market_outcomes mo on mo.condition_id = w.condition_id
where w.platform = 'polymarket' and w.side = 0 and w.traded_at >= date '2026-04-02' and w.traded_at < date '2026-09-14'
  and mo.resolved_at > w.traded_at and w.price_num between 0.02 and 0.98;
select side, count(*) buys, count(distinct condition_id) markets, round(sum(usdc_notional_num)/1e6, 1) notional_musd,
       round(avg(price_num)*100, 1) avg_price_c, round(avg(won)::numeric*100, 1) win_pct,
       round((avg(won)::numeric - avg(price_num))*100, 2) edge_pts,
       round((sum(usdc_notional_num*(won/price_num - 1))/sum(usdc_notional_num))*100, 2) dollar_roi_pct
from bb group by rollup(1) order by 1;

-- 10. Market-level export for the clustered bootstrap.
\copy (select side as grp, condition_id, count(*) n, sum(won::numeric - price_num) sum_edge from bb group by 1, 2) to './btts-market-edge.csv' with (format csv, header true)

-- 11. Complete halftime events: both "<team> leading at halftime?" markets and the "Draw at halftime?" market settled
-- for one match. Exactly one should resolve Yes. Home is the first-named team in the draw market's title; the team
-- markets carry the team name in group_item_title, and home_name_unmatched counts events where neither team
-- market carries the home name (the home/away split is only read when that is zero).
create temp table ht_home as
select base_slug, split_part(title, ' vs. ', 1) home from ht where kind = 'draw';
select count(*) matches, count(*) filter (where yes_count = 1) exactly_one_yes,
       round(100.0*avg(level::int), 1) level_pct, round(100.0*avg(home_led::int), 1) home_leading_pct,
       round(100.0*avg(away_led::int), 1) away_leading_pct, count(*) filter (where team_named_home = 0) home_name_unmatched,
       min(ko)::date first_kickoff
from (
  select h.base_slug, min(h.game_start_time) ko,
         count(*) filter (where h.winning_outcome = 0) yes_count,
         bool_or(h.kind = 'draw' and h.winning_outcome = 0) level,
         bool_or(h.kind = 'team' and h.winning_outcome = 0 and h.group_item_title = hh.home) home_led,
         bool_or(h.kind = 'team' and h.winning_outcome = 0 and h.group_item_title <> hh.home) away_led,
         count(*) filter (where h.kind = 'team' and h.group_item_title = hh.home) team_named_home,
         count(*) filter (where h.kind = 'team') teams, count(*) filter (where h.kind = 'draw') draws
  from ht h join ht_home hh using (base_slug)
  group by 1
) e where teams = 2 and draws = 1;
