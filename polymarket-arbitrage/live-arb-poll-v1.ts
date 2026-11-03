// Watch three-way soccer sets through a live match: every few seconds, the cost of one share of
// home, draw and away YES at the best ask, and at depth, from Polymarket's public CLOB books.
// The legs and the live score come from the 0xinsider games API, so a goal can be lined up
// against the sum. Writes one JSON line per poll. It places no orders.
// Run: OXINSIDER_API_KEY=... node live-arb-poll.ts ucl-mnu-rom-2026-11-03 [more slugs] > live.jsonl
//      env EVERY_MS (default 5000) and UNTIL (ISO time, default three hours from now).
const API = "https://api.0xinsider.com/api/v1";
const CLOB = "https://clob.polymarket.com";
const KEY = process.env.OXINSIDER_API_KEY;
if (!KEY) throw new Error("set OXINSIDER_API_KEY (a Pro or Max key)");
const EVERY_MS = Number(process.env.EVERY_MS ?? 5000);
const UNTIL = Date.parse(process.env.UNTIL ?? new Date(Date.now() + 3 * 3600_000).toISOString());
const SIZES = [100, 1000];

interface Game {
  data: {
    event_slug: string;
    status: { state: string; period?: string; clock?: string; ended: boolean };
    competitors: { name: string; score?: string }[];
    markets: { slug: string; side: "home" | "away" | "draw"; outcome_token_ids: string[] }[];
  };
}
interface Book { asset_id: string; bids: { price: string; size: string }[]; asks: { price: string; size: string }[] }

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
const game = (slug: string) => getJson<Game>(`${API}/games/${slug}`, { headers: { Authorization: `Bearer ${KEY}` } });

// Cost of `size` shares bought up the ask ladder, per share; null when the book is too thin.
function costPerShare(asks: Book["asks"], size: number): number | null {
  let left = size;
  let spent = 0;
  for (const level of [...asks].sort((a, b) => Number(a.price) - Number(b.price))) {
    const take = Math.min(left, Number(level.size));
    spent += take * Number(level.price);
    left -= take;
    if (left <= 0) return spent / size;
  }
  return null;
}

const slugs = process.argv.slice(2);
const sets = await Promise.all(
  slugs.map(async (slug) => {
    const g = (await game(slug)).data;
    const legs = (["home", "draw", "away"] as const).map((side) => {
      const m = g.markets.find((x) => x.side === side);
      if (!m) throw new Error(`${slug}: no ${side} leg`);
      return { side, slug: m.slug, yes: m.outcome_token_ids[0] };
    });
    return { slug, legs, score: "", state: g.status.state, clock: "" };
  }),
);

let lastScoreRead = 0;
while (Date.now() < UNTIL) {
  const started = Date.now();
  try {
  if (started - lastScoreRead >= 30_000) {
    lastScoreRead = started;
    await Promise.all(
      sets.map(async (s) => {
        const g = (await game(s.slug)).data;
        s.score = g.competitors.map((c) => c.score ?? "").join("-");
        s.state = g.status.ended ? "ended" : g.status.state;
        s.clock = [g.status.period, g.status.clock].filter(Boolean).join(" ");
      }),
    );
  }
  const tokens = sets.flatMap((s) => s.legs.map((l) => l.yes));
  const books: Book[] = [];
  for (let i = 0; i < tokens.length; i += 25) {
    const body = JSON.stringify(tokens.slice(i, i + 25).map((token_id) => ({ token_id })));
    books.push(...(await getJson<Book[]>(`${CLOB}/books`, { method: "POST", body, headers: { "Content-Type": "application/json" } })));
  }
  const byToken = new Map(books.map((b) => [b.asset_id, b]));
  const at = new Date().toISOString();
  for (const s of sets) {
    const legBooks = s.legs.map((l) => byToken.get(l.yes));
    if (legBooks.some((b) => b === undefined)) continue;
    const bestAsk = legBooks.map((b) => Math.min(...b!.asks.map((a) => Number(a.price))));
    const bestBid = legBooks.map((b) => Math.max(...b!.bids.map((a) => Number(a.price))));
    const depth = Object.fromEntries(
      SIZES.map((size) => {
        const costs = legBooks.map((b) => costPerShare(b!.asks, size));
        return [size, costs.some((c) => c === null) ? null : Number(costs.reduce((x, c) => x! + c!, 0)!.toFixed(4))];
      }),
    );
    console.log(
      JSON.stringify({
        at,
        slug: s.slug,
        state: s.state,
        clock: s.clock,
        score: s.score,
        asks: bestAsk,
        bids: bestBid,
        sumAsks: Number(bestAsk.reduce((x, y) => x + y, 0).toFixed(4)),
        sumBids: Number(bestBid.reduce((x, y) => x + y, 0).toFixed(4)),
        setCost: depth,
      }),
    );
  }
  } catch (err) {
    // A failed poll is reported and skipped, so one timeout does not end a two-hour watch.
    console.error(JSON.stringify({ at: new Date().toISOString(), error: String(err) }));
  }
  if (sets.every((s) => s.state === "ended")) break;
  await new Promise((r) => setTimeout(r, Math.max(0, EVERY_MS - (Date.now() - started))));
}
