# AGENTS.md - research

Instructions for AI coding agents working in this repository. This repository holds the SQL, raw query output, and market-clustered bootstraps behind the Polymarket studies published at https://0xinsider.com/research.

0xinsider is Polymarket analytics for sports and esports in real-time: large
trades, wallet grades, sharp-money flow, positions, and research.

## Install

```
git clone https://github.com/0xinsider/research
```

## Read before writing integration code

The canonical agent rules live in the official Agent Plugin:
<https://github.com/0xinsider/agent-plugin/blob/main/AGENTS.md>. Install the
whole plugin, including five skills covering API access, large trades, wallet
grades, sharp-money flow, and market research:

```bash
npx skills add 0xinsider/agent-plugin
```

## Rules that apply here

- **Use the sandbox first.** `https://0xinsider.com/sandbox` answers every
  documented operation with no credential and no production data. Add
  `?sandbox_status=<code>` to exercise an error path.
- **Read credentials from the environment** (`OXINSIDER_API_KEY`). Never write
  a key into a config file, a committed script, or an example.
- **The OpenAPI spec is the source of truth.** This client is generated from
  <https://0xinsider.com/api/v1/openapi.json>. Regenerate rather than hand-edit
  generated files.
- **Batch instead of looping.** Batch reads accept 25 items against a
  100-request-per-minute budget.
- **Branch on `error.code`, never the message string.**
- **Follow cursors to completion.** Feeds and timelines are paged and move
  while you read them. Never page by offset, never total a partial page.
- **Send `Idempotency-Key` on writes,** and reuse it across retries.

## Rules for presenting the data

These are correctness requirements. Getting them wrong produces a confident,
wrong number.

- An absent field is not a zero. Serve a truthful unavailable state.
- `pnl.realized` is omitted when no native accounting snapshot matches. Raw
  total P&L is never a substitute for it.
- The 0.0-1.0 significance score ranks attention, not outcomes. It is a
  different quantity from Insider Radar's 0-100 suspicion score. Neither is a
  probability or a forecast.
- `BUY YES` and `SELL NO` add exposure; `BUY NO` and `SELL YES` subtract it.
  A zero-flow YES tie-break is not conviction.
- An ungraded wallet is uncovered, not unskilled.
- Keep full numeric precision until the final render.
- Every polymarket.com link carries `?r=0xinsidercom`.

## Conventions

- No emojis, in code, docs, commits, or issues. Use plain-text markers.
- Every published figure traces to a query in this repository. When you cite a number, cite the query file and the run date with it; a result without its run date is not auditable.

## Official resources

| Resource | URL |
| --- | --- |
| Developer portal | https://0xinsider.com/developers |
| API documentation | https://docs.0xinsider.com |
| OpenAPI 3.1 spec | https://0xinsider.com/api/v1/openapi.json |
| Authentication | https://0xinsider.com/auth.md |
| Agent instructions | https://0xinsider.com/agents.md |
| Machine-readable index | https://0xinsider.com/llms.txt |
| Remote MCP endpoint | https://0xinsider.com/mcp |
| Agent Plugin and skills | https://github.com/0xinsider/agent-plugin |
| Python SDK | https://github.com/0xinsider/0xinsider-python |
| Go SDK | https://github.com/0xinsider/0xinsider-go |
| CLI and MCP package | https://www.npmjs.com/package/@0xinsider/mcp |
