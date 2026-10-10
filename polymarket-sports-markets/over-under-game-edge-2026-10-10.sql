-- #22294: the corrected over/under buy-level edges, clustered by game, the step query 4 of
-- over-under-by-game.sql ran for the September export. It joins each market of
-- over-under-2026-10-10-market-edge.csv (the corrected run, void and unresolvable markets left out) to its
-- game so over-under-game-bootstrap-2026-10-10.py can resample games instead of markets. Read-only; the temp
-- table lives only in this session. Ran on the same Neon child branch as over-under-2026-10-10.sql:
--   ./scripts/neon-child-branch.sh query --name <branch> -f over-under-game-edge-2026-10-10.sql
select now() as run_at;
create temp table edge (grp text, condition_id text, n integer, sum_edge numeric);
\copy edge from 'over-under-2026-10-10-market-edge.csv' with csv header
select count(*) edge_rows, count(m.condition_id) joined_to_a_market, count(distinct m.event_slug) games from edge e left join markets m on m.condition_id = e.condition_id;
\copy (select e.grp, m.event_slug, sum(e.n) n, sum(e.sum_edge) sum_edge from edge e join markets m on m.condition_id = e.condition_id group by 1, 2 order by 1, 2) to 'over-under-game-edge-2026-10-10.csv' with csv header
