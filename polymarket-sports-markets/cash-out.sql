-- Study 8: cashing out. When a large Polymarket sports bettor sells before settlement, is the exit price fair?
-- Read-only. Read-only role against production.  psql "$DATABASE_URL" -X -f cash-out.sql
-- Window 2026-04-02 .. 2026-09-13 (see the calibration study for why April 2). Grades from 2026-06-01, point-in-time.
-- Universe: every large-trade alert for a Polymarket SELL (side = 1) on a sports-category market, 2c-98c,
-- on a market that settled after the trade. A sell of outcome X at price p gives up a share that pays $1 if X
-- happens. Value given up = (1 if X happened else 0) - p per share. Averaged: the sold outcome's win rate minus
-- the average exit price, in points. Positive = the seller let go of an outcome worth more than the exit price.
-- The dollar figure is what holding the same shares to settlement would have returned on the cash received:
-- sum(cash * (won / p - 1)) / sum(cash). Nothing here knows the seller's entry price.
select now() as run_at;

create temp view sells as
select w.id, w.trader_id, w.condition_id, w.traded_at, w.outcome_index, w.price_num, w.usdc_notional_num, w.category,
       m.sports_market_type, m.game_start_time,
       case when m.game_start_time is null then 'unknown' when w.traded_at < m.game_start_time then 'pre-kickoff' else 'in-play' end phase,
       (w.outcome_index = mo.winning_outcome)::int as won
from whale_alerts w
join market_outcomes mo on mo.condition_id = w.condition_id
left join markets m on m.condition_id = w.condition_id
where w.platform = 'polymarket' and w.side = 1
  and w.traded_at >= date '2026-04-02' and w.traded_at < date '2026-09-14'
  and w.category in ('Soccer','NBA','Esports','Tennis','Baseball','Hockey','Basketball','Cricket',
                     'MMA','NFL','Golf','WNBA','Formula 1','Boxing','NCAAF','NCAAB','Table Tennis',
                     'NBA Summer League','CFL','Sports','Big Game','Pickleball')
  and mo.winning_outcome is not null and mo.resolved_at > w.traded_at
  and w.price_num between 0.02 and 0.98;

-- 1. Sample.
select count(*) sells, count(distinct trader_id) wallets, count(distinct condition_id) markets, round(sum(usdc_notional_num)/1e6,1) cash_musd,
       round(100.0*count(*) filter (where phase = 'in-play')/count(*),1) in_play_pct, round(avg(usdc_notional_num)) avg_cash_usd
from sells;

-- 2. All sells: value given up, and the buy side of the same universe for comparison.
select 'sells' side, count(*) n, round(avg(price_num)*100,1) avg_price_c, round(avg(won)::numeric*100,1) sold_outcome_won_pct,
       round((avg(won)::numeric - avg(price_num))*100,2) value_given_up_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100,2) hold_return_pct
from sells
union all
select 'buys', count(*), round(avg(w.price_num)*100,1), round(avg((w.outcome_index = mo.winning_outcome)::int)::numeric*100,1),
       round((avg((w.outcome_index = mo.winning_outcome)::int)::numeric - avg(w.price_num))*100,2),
       round((sum(w.usdc_notional_num*((w.outcome_index = mo.winning_outcome)::int/w.price_num-1))/sum(w.usdc_notional_num))*100,2)
from whale_alerts w join market_outcomes mo on mo.condition_id = w.condition_id
where w.platform = 'polymarket' and w.side = 0 and w.traded_at >= date '2026-04-02' and w.traded_at < date '2026-09-14'
  and w.category in ('Soccer','NBA','Esports','Tennis','Baseball','Hockey','Basketball','Cricket','MMA','NFL','Golf','WNBA','Formula 1','Boxing','NCAAF','NCAAB','Table Tennis','NBA Summer League','CFL','Sports','Big Game','Pickleball')
  and mo.winning_outcome is not null and mo.resolved_at > w.traded_at and w.price_num between 0.02 and 0.98;

-- 3. By exit price.
select case when price_num < 0.10 then 'a. under 10c' when price_num < 0.20 then 'b. 10-20c' when price_num < 0.40 then 'c. 20-40c'
            when price_num < 0.60 then 'd. 40-60c' when price_num < 0.80 then 'e. 60-80c' when price_num < 0.90 then 'f. 80-90c' else 'g. 90-98c' end band,
       count(*) n, count(distinct condition_id) markets, round(sum(usdc_notional_num)/1e6,1) cash_musd,
       round(avg(price_num)*100,1) avg_price_c, round(avg(won)::numeric*100,1) sold_outcome_won_pct,
       round((avg(won)::numeric - avg(price_num))*100,2) value_given_up_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100,2) hold_return_pct,
       round(100.0*count(*) filter (where phase = 'in-play')/count(*),1) in_play_pct
from sells group by 1 order by 1;

-- 4. Phase x exit price group.
select phase, case when price_num < 0.20 then 'a. under 20c' when price_num < 0.80 then 'b. 20-80c' else 'c. 80c+' end grp,
       count(*) n, count(distinct condition_id) markets, round(avg(price_num)*100,1) avg_price_c, round(avg(won)::numeric*100,1) sold_outcome_won_pct,
       round((avg(won)::numeric - avg(price_num))*100,2) value_given_up_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100,2) hold_return_pct
from sells where phase <> 'unknown' group by 1,2 order by 1,2;

-- 5. Grade cohort x exit price group, June 1 onward.
with g as (
  select s.*, case when gr.grade in ('S','A','B') then 'S/A/B' when gr.grade = 'C' then 'C' when gr.grade in ('D','F') then 'D/F' else 'no grade' end cohort
  from sells s left join lateral (select tr.grade from trader_rankings tr where tr.trader_id = s.trader_id and tr.date <= s.traded_at::date order by tr.date desc limit 1) gr on true
  where s.traded_at >= date '2026-06-01')
select cohort, case when price_num < 0.20 then 'a. under 20c' when price_num < 0.80 then 'b. 20-80c' else 'c. 80c+' end grp,
       count(*) n, round(avg(price_num)*100,1) avg_price_c, round(avg(won)::numeric*100,1) sold_outcome_won_pct,
       round((avg(won)::numeric - avg(price_num))*100,2) value_given_up_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100,2) hold_return_pct
from g group by rollup(1,2) order by 1,2;

-- 6. By sport, 1,000 or more sells.
select category sport, count(*) n, round(avg(price_num)*100,1) avg_price_c, round(avg(won)::numeric*100,1) sold_outcome_won_pct,
       round((avg(won)::numeric - avg(price_num))*100,2) value_given_up_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100,2) hold_return_pct,
       round(100.0*count(*) filter (where phase = 'in-play')/count(*),1) in_play_pct
from sells group by 1 having count(*) >= 1000 order by 2 desc;

-- 7. By market type.
select coalesce(sports_market_type, '(untyped)') market_type, count(*) n, round(avg(price_num)*100,1) avg_price_c,
       round((avg(won)::numeric - avg(price_num))*100,2) value_given_up_pts,
       round((sum(usdc_notional_num*(won/price_num-1))/sum(usdc_notional_num))*100,2) hold_return_pct
from sells group by 1 having count(*) >= 1000 order by 2 desc;

-- 8. Concentration in the under-20c band: the ten markets with the most sells.
with t as (select condition_id, count(*) n, max(won) won, round(avg(price_num)*100,1) avg_price_c, sum(usdc_notional_num) cash from sells where price_num < 0.20 group by 1)
select t.condition_id, t.n, t.won, t.avg_price_c, round(t.cash) cash_usd, m.title, m.category
from t left join markets m on m.condition_id = t.condition_id order by t.n desc limit 10;

-- 9. The under-20c band without its single largest market.
with top1 as (select condition_id from sells where price_num < 0.20 group by 1 order by count(*) desc limit 1)
select count(*) n, count(distinct condition_id) markets, round(avg(price_num)*100,1) avg_price_c, round(avg(won)::numeric*100,1) sold_outcome_won_pct,
       round((avg(won)::numeric - avg(price_num))*100,2) value_given_up_pts
from sells where price_num < 0.20 and condition_id not in (select condition_id from top1);

-- 10. Month.
select date_trunc('month', traded_at)::date mo, count(*) n, round(avg(price_num)*100,1) avg_price_c,
       round((avg(won)::numeric - avg(price_num))*100,2) value_given_up_pts
from sells group by 1 order by 1;

-- 11. Market-level export for the clustered bootstrap: all, exit band, phase x group, cohort x group.
\copy (select grp, condition_id, count(*) n, sum(won::numeric - price_num) sum_edge from (select 'all sells' grp, condition_id, won, price_num from sells union all select 'band ' || case when price_num < 0.10 then 'a. under 10c' when price_num < 0.20 then 'b. 10-20c' when price_num < 0.40 then 'c. 20-40c' when price_num < 0.60 then 'd. 40-60c' when price_num < 0.80 then 'e. 60-80c' when price_num < 0.90 then 'f. 80-90c' else 'g. 90-98c' end, condition_id, won, price_num from sells union all select phase || ' ' || case when price_num < 0.20 then 'under 20c' when price_num < 0.80 then '20-80c' else '80c+' end, condition_id, won, price_num from sells where phase <> 'unknown' union all select g.cohort || ' ' || case when g.price_num < 0.20 then 'under 20c' when g.price_num < 0.80 then '20-80c' else '80c+' end, g.condition_id, g.won, g.price_num from (select s.*, case when gr.grade in ('S','A','B') then 'S/A/B' when gr.grade in ('D','F') then 'D/F' else 'other' end cohort from sells s left join lateral (select tr.grade from trader_rankings tr where tr.trader_id = s.trader_id and tr.date <= s.traded_at::date order by tr.date desc limit 1) gr on true where s.traded_at >= date '2026-06-01') g where g.cohort in ('S/A/B','D/F')) x group by 1,2) to './cash-out-market-edge.csv' with (format csv, header true)
