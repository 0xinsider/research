-- Study 15 (#13943) supplement: where the money goes on a CS2/Valorant/Dota 2/LoL esports series on
-- Polymarket, for the guide at /learn/how-to-bet-on-esports-polymarket. Read-only, a read-only role.
--   psql "$DATABASE_URL" -X -f esports-markets.sql
select now() as run_at;

-- 1. Settled markets and volume on the four games since 2025-01-01, by market family.
with fam as (
  select m.condition_id, m.volume,
    case
      when m.sports_market_type = 'moneyline' then 'Series moneyline'
      when m.sports_market_type = 'child_moneyline' then 'Map/Game winner'
      when m.sports_market_type = 'map_handicap' then 'Map handicap'
      when m.sports_market_type = 'totals' then 'Games total'
      when m.sports_market_type in ('round_over_under_game_1','round_over_under_game_2','round_over_under_game_3',
        'round_over_under_game_4','round_over_under_game_5','round_over_under_match',
        'round_handicap_game_1','round_handicap_game_2','round_handicap_game_3','round_handicap_game_4',
        'round_handicap_game_5','round_handicap_match') then 'Round props'
      when m.sports_market_type in ('kill_over_under_game','kill_handicap_match','kill_most_2_way_match',
        'cs2_odd_even_total_kills','cs2_odd_even_total_rounds','lol_odd_even_total_kills',
        'first_blood_game') then 'Kill props'
      else 'Everything else'
    end as family
  from markets m join market_outcomes mo on mo.condition_id = m.condition_id
  where m.category = 'Esports' and mo.winning_outcome in (0, 1)
    and split_part(m.event_slug, '-', 1) in ('cs2', 'val', 'valorant', 'dota2', 'lol')
    and m.game_start_time >= '2025-01-01'
)
select family, count(*) markets, round(sum(volume)) volume_usd,
       round(100.0 * sum(volume) / sum(sum(volume)) over (), 1) share_pct
from fam group by 1 order by volume_usd desc;

-- 2. Total, for the denominator.
with fam as (
  select m.condition_id, m.volume
  from markets m join market_outcomes mo on mo.condition_id = m.condition_id
  where m.category = 'Esports' and mo.winning_outcome in (0, 1)
    and split_part(m.event_slug, '-', 1) in ('cs2', 'val', 'valorant', 'dota2', 'lol')
    and m.game_start_time >= '2025-01-01'
)
select count(*) markets, round(sum(volume)) volume_usd from fam;
