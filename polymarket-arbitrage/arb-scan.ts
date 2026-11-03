// Three-way soccer arbitrage scan. Lists every scheduled and live soccer game with a home, draw
// and away market from the 0xinsider games API, reads each leg's YES and NO books from
// Polymarket's public CLOB and its fee schedule from Gamma, then asks four questions per set:
// do the best YES asks sum below $1, do the best YES bids sum above $1, what does a full set
// cost at depth, and what does the taker fee add. It places no orders.
// Run: OXINSIDER_API_KEY=... node arb-scan.ts > arb-scan.json
const API = "https://api.0xinsider.com/api/v1";
const CLOB = "https://clob.polymarket.com";
const GAMMA = "https://gamma-api.polymarket.com";
const KEY = process.env.OXINSIDER_API_KEY;
if (!KEY) throw new Error("set OXINSIDER_API_KEY (a Pro or Max key)");
const SIZES = [100, 500, 1000, 5000];

type Side = "home" | "draw" | "away";
interface GameRow {
  event_slug: string;
  league: string;
  scheduled_at: string;
  status: { state: string };
  markets: { condition_id: string; slug: string; side: Side; outcome_token_ids: string[] }[];
}
interface Level { price: string; size: string }
interface Book { asset_id: string; bids: Level[]; asks: Level[]; neg_risk?: boolean }

async function getJson<T>(url: string, init?: RequestInit): Promise<T> {
  for (let attempt = 0; ; attempt++) {
    const res = await fetch(url, init);
    if ((res.status === 429 || res.status >= 500) && attempt < 4) {
      await new Promise((r) => setTimeout(r, 1000 * 2 ** attempt));
      continue;
    }
    if (!res.ok) throw new Error(`${res.status} ${url}: ${(await res.text()).slice(0, 200)}`);
    return (await res.json()) as T;
  }
}

// 1. Games and their three legs, from the 0xinsider API.
const games: GameRow[] = [];
for (const status of ["scheduled", "live"]) {
  let cursor: string | null = null;
  do {
    const q = new URLSearchParams({ sport: "soccer", status, limit: "100" });
    if (cursor) q.set("cursor", cursor);
    const page = await getJson<{ data: GameRow[]; has_more: boolean; next_cursor: string | null }>(`${API}/games?${q}`, {
      headers: { Authorization: `Bearer ${KEY}` },
    });
    games.push(...page.data);
    cursor = page.has_more ? page.next_cursor : null;
  } while (cursor);
}
const sets = games
  .map((g) => {
    const legs = (["home", "draw", "away"] as const).map((side) => g.markets.filter((m) => m.side === side));
    if (legs.some((l) => l.length !== 1)) return null;
    return { event: g.event_slug, league: g.league, kickoff: g.scheduled_at, state: g.status.state, legs: legs.map((l) => l[0]!) };
  })
  .filter((s) => s !== null);

// 2. Books for both tokens of every leg, 25 a request.
const tokens = sets.flatMap((s) => s.legs.flatMap((l) => l.outcome_token_ids.slice(0, 2)));
const books = new Map<string, Book>();
for (let i = 0; i < tokens.length; i += 25) {
  const body = JSON.stringify(tokens.slice(i, i + 25).map((token_id) => ({ token_id })));
  for (const b of await getJson<Book[]>(`${CLOB}/books`, { method: "POST", body, headers: { "Content-Type": "application/json" } })) books.set(b.asset_id, b);
}

// 3. Fee schedules from Gamma, 50 condition ids a request.
const fees = new Map<string, { rate: number; takerOnly: boolean } | null>();
const conditions = sets.flatMap((s) => s.legs.map((l) => l.condition_id));
for (let i = 0; i < conditions.length; i += 50) {
  const q = new URLSearchParams({ limit: "50" });
  for (const c of conditions.slice(i, i + 50)) q.append("condition_ids", c);
  for (const m of await getJson<{ conditionId: string; feeSchedule?: { rate: number; takerOnly: boolean } | null }[]>(`${GAMMA}/markets?${q}`))
    fees.set(m.conditionId, m.feeSchedule ?? null);
}

const best = (levels: Level[], pick: "min" | "max") => {
  const prices = levels.map((l) => Number(l.price));
  return prices.length === 0 ? null : pick === "min" ? Math.min(...prices) : Math.max(...prices);
};
// Buy `size` shares up the ask ladder: average price and taker fee per share, or null if too thin.
function walk(asks: Level[], size: number, rate: number) {
  let left = size;
  let spent = 0;
  let fee = 0;
  for (const l of [...asks].sort((a, b) => Number(a.price) - Number(b.price))) {
    const p = Number(l.price);
    const take = Math.min(left, Number(l.size));
    spent += take * p;
    fee += take * rate * p * (1 - p);
    left -= take;
    if (left <= 0) return { price: spent / size, fee: fee / size };
  }
  return null;
}
const r4 = (x: number) => Number(x.toFixed(4));

const rows = sets.flatMap((s) => {
  const yes = s.legs.map((l) => books.get(l.outcome_token_ids[0]!));
  const no = s.legs.map((l) => books.get(l.outcome_token_ids[1]!));
  if (yes.some((b) => !b) || no.some((b) => !b)) return [];
  const asks = yes.map((b) => best(b!.asks, "min"));
  const bids = yes.map((b) => best(b!.bids, "max"));
  if (asks.some((a) => a === null) || bids.some((b) => b === null)) return [];
  const rates = s.legs.map((l) => fees.get(l.condition_id)?.rate ?? 0);
  const sumAsks = asks.reduce((x, a) => x! + a!, 0)!;
  const sumBids = bids.reduce((x, b) => x! + b!, 0)!;
  const feeAtBest = asks.reduce((x, a, i) => x + rates[i]! * a! * (1 - a!), 0);
  // Binary identity per leg: YES ask + NO ask - 1 against the YES spread.
  const binary = s.legs.map((_, i) => {
    const noAsk = best(no[i]!.asks, "min");
    return noAsk === null ? null : r4(asks[i]! + noAsk - 1 - (asks[i]! - bids[i]!));
  });
  const depth = Object.fromEntries(
    SIZES.map((size) => {
      const legs = yes.map((b, i) => walk(b!.asks, size, rates[i]!));
      if (legs.some((l) => l === null)) return [size, null];
      return [size, { cost: r4(legs.reduce((x, l) => x + l!.price, 0)), fee: r4(legs.reduce((x, l) => x + l!.fee, 0)) }];
    }),
  );
  return [{ event: s.event, league: s.league, kickoff: s.kickoff, state: s.state, negRisk: yes.every((b) => b!.neg_risk === true), asks, bids, rates, sumAsks: r4(sumAsks), sumBids: r4(sumBids), feeAtBest: r4(feeAtBest), binaryGap: binary, depth }];
});

const sorted = (xs: number[]) => [...xs].sort((a, b) => a - b);
const median = (xs: number[]) => {
  const s = sorted(xs);
  return s.length === 0 ? null : s.length % 2 ? s[(s.length - 1) / 2]! : (s[s.length / 2 - 1]! + s[s.length / 2]!) / 2;
};
const hist = (xs: number[]) => {
  const h = new Map<string, number>();
  for (const x of xs) {
    const k = (Math.round(x * 100) / 100).toFixed(2);
    h.set(k, (h.get(k) ?? 0) + 1);
  }
  return Object.fromEntries([...h].sort((a, b) => Number(a[0]) - Number(b[0])));
};
const sumAsks = rows.map((r) => r.sumAsks);
const sumBids = rows.map((r) => r.sumBids);
const binaryGaps = rows.flatMap((r) => r.binaryGap).filter((g) => g !== null);
console.log(
  JSON.stringify(
    {
      readAt: new Date().toISOString(),
      games: games.length,
      threeWaySets: sets.length,
      priced: rows.length,
      negRisk: rows.filter((r) => r.negRisk).length,
      byState: Object.fromEntries(["scheduled", "live"].map((st) => [st, rows.filter((r) => r.state === st).length])),
      sumAsks: { min: Math.min(...sumAsks), median: median(sumAsks), max: Math.max(...sumAsks), below1: sumAsks.filter((x) => x < 1).length, atMost101: sumAsks.filter((x) => x <= 1.01).length, hist: hist(sumAsks) },
      sumBids: { min: Math.min(...sumBids), median: median(sumBids), max: Math.max(...sumBids), above1: sumBids.filter((x) => x > 1).length },
      feeAtBest: { median: median(rows.map((r) => r.feeAtBest)), min: Math.min(...rows.map((r) => r.feeAtBest)), max: Math.max(...rows.map((r) => r.feeAtBest)) },
      feeRates: Object.fromEntries([...new Set(rows.flatMap((r) => r.rates))].map((rate) => [rate, rows.flatMap((r) => r.rates).filter((x) => x === rate).length])),
      afterFeeBelow1: rows.filter((r) => r.sumAsks + r.feeAtBest < 1).length,
      binaryIdentity: { legs: binaryGaps.length, nonZero: binaryGaps.filter((g) => Math.abs(g) > 1e-9).length, maxAbs: Math.max(0, ...binaryGaps.map(Math.abs)) },
      depthBySize: Object.fromEntries(
        SIZES.map((size) => {
          const ok = rows.map((r) => r.depth[size]).filter((d) => d !== null);
          return [size, { fillable: ok.length, minCost: Math.min(...ok.map((d) => d.cost)), medianCost: median(ok.map((d) => d.cost)), below1: ok.filter((d) => d.cost < 1).length, belowOneAfterFee: ok.filter((d) => d.cost + d.fee < 1).length }];
        }),
      ),
      cheapest: [...rows].sort((a, b) => a.sumAsks - b.sumAsks).slice(0, 10),
      rows,
    },
    null,
    1,
  ),
);
