// How deep is a Polymarket sports moneyline book by hours to the start, and once the game is live?
// Pages Gamma's open sports events, keeps every moneyline that accepts orders and has a start time,
// buckets it by start time against now (Gamma's event `live` flag marks in-play), reads the Yes book
// from the public CLOB, and reports the median spread and the dollars resting within 2 and 5 cents
// of the midpoint per bucket. Also counts Gamma's secondsDelay by league. Public data, no key.
// Run: node depth-by-kickoff.ts > depth-by-kickoff.json
const GAMMA = "https://gamma-api.polymarket.com";
const CLOB = "https://clob.polymarket.com";

interface Market {
  conditionId: string;
  sportsMarketType?: string;
  acceptingOrders?: boolean;
  gameStartTime?: string;
  clobTokenIds?: string;
  secondsDelay?: number | null;
}
interface Event { slug: string; live?: boolean | null; ended?: boolean | null; seriesSlug?: string; series?: { slug: string }[]; tags?: { slug: string }[]; markets?: Market[] }
interface Level { price: string; size: string }
interface Book { asset_id: string; bids: Level[]; asks: Level[] }

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

const now = Date.now();
const events: Event[] = [];
// Gamma answers 422 past an offset of about 2,000, which ends the paging.
for (let offset = 0; ; offset += 100) {
  const q = new URLSearchParams({ tag_slug: "sports", closed: "false", order: "volume24hr", ascending: "false", limit: "100", offset: String(offset) });
  const res = await fetch(`${GAMMA}/events?${q}`);
  if (res.status === 422) break;
  if (!res.ok) throw new Error(`${res.status} events offset ${offset}`);
  const page = (await res.json()) as Event[];
  if (page.length === 0) break;
  events.push(...page);
}

const BUCKETS = ["in-play", "<1h", "1-3h", "3-6h", "6-24h", "1-3d", "3-7d", "7d+"] as const;
type Bucket = (typeof BUCKETS)[number];
const bucket = (hours: number): Bucket =>
  hours < 1 ? "<1h" : hours < 3 ? "1-3h" : hours < 6 ? "3-6h" : hours < 24 ? "6-24h" : hours < 72 ? "1-3d" : hours < 168 ? "3-7d" : "7d+";
// Gamma writes "2026-11-03 20:00:00+00"; Date.parse needs the T and a full offset.
const parseStart = (s: string) => Date.parse(s.replace(" ", "T").replace(/\+00$/, "+00:00"));

const rows = events.flatMap((e) => {
  const league = e.series?.[0]?.slug ?? e.seriesSlug ?? e.tags?.find((t) => !["sports", "games"].includes(t.slug))?.slug ?? "";
  return (e.markets ?? []).flatMap((m) => {
    if (m.sportsMarketType !== "moneyline" || !m.acceptingOrders || !m.gameStartTime || !m.clobTokenIds) return [];
    const start = parseStart(m.gameStartTime);
    if (Number.isNaN(start)) return [];
    const hours = (start - now) / 3_600_000;
    // A start time in the past on a game Gamma does not call live is stale (postponed, or not yet
    // marked); it is left out rather than guessed into a bucket.
    if (hours < 0 && e.live !== true) return [];
    const b: Bucket = e.live === true ? "in-play" : bucket(hours);
    return [{ event: e.slug, league, soccer: (e.tags ?? []).some((t) => t.slug === "soccer"), bucket: b, token: (JSON.parse(m.clobTokenIds) as string[])[0]!, delay: m.secondsDelay ?? null }];
  });
});

const books = new Map<string, Book>();
for (let i = 0; i < rows.length; i += 25) {
  const body = JSON.stringify(rows.slice(i, i + 25).map((r) => ({ token_id: r.token })));
  for (const b of await getJson<Book[]>(`${CLOB}/books`, { method: "POST", body, headers: { "Content-Type": "application/json" } })) books.set(b.asset_id, b);
}
const near = (b: Book, mid: number, band: number) =>
  [...b.bids, ...b.asks].filter((l) => Math.abs(Number(l.price) - mid) <= band + 1e-9).reduce((x, l) => x + Number(l.price) * Number(l.size), 0);
const median = (xs: number[]) => {
  const s = [...xs].sort((a, b) => a - b);
  return s.length === 0 ? null : s.length % 2 ? s[(s.length - 1) / 2]! : (s[s.length / 2 - 1]! + s[s.length / 2]!) / 2;
};
const quantile = (xs: number[], q: number) => {
  const s = [...xs].sort((a, b) => a - b);
  return s.length === 0 ? null : s[Math.min(s.length - 1, Math.floor(q * s.length))]!;
};

const priced = rows.flatMap((r) => {
  const b = books.get(r.token);
  if (!b || b.bids.length === 0 || b.asks.length === 0) return [];
  const bid = Math.max(...b.bids.map((x) => Number(x.price)));
  const ask = Math.min(...b.asks.map((x) => Number(x.price)));
  const mid = (bid + ask) / 2;
  return [{ ...r, spreadC: Number(((ask - bid) * 100).toFixed(2)), usd2c: near(b, mid, 0.02), usd5c: near(b, mid, 0.05) }];
});

const byBucket = BUCKETS.map((k) => {
  const xs = priced.filter((p) => p.bucket === k);
  return {
    bucket: k,
    books: xs.length,
    medianSpreadC: median(xs.map((x) => x.spreadC)),
    p90SpreadC: quantile(xs.map((x) => x.spreadC), 0.9),
    medianUsd2c: xs.length ? Math.round(median(xs.map((x) => x.usd2c))!) : null,
    medianUsd5c: xs.length ? Math.round(median(xs.map((x) => x.usd5c))!) : null,
  };
});
const delays = new Map<string, number>();
for (const r of rows) delays.set(`${r.league}|${String(r.delay)}`, (delays.get(`${r.league}|${String(r.delay)}`) ?? 0) + 1);
console.log(JSON.stringify({
  readAt: new Date(now).toISOString(),
  events: events.length,
  moneylines: rows.length,
  twoSided: priced.length,
  delayCounts: Object.fromEntries(["1", "0", "null"].map((d) => [d, rows.filter((r) => String(r.delay) === d).length])),
  byBucket,
  delayByLeague: [...delays].map(([k, n]) => ({ league: k.split("|")[0], delay: k.split("|")[1], markets: n })).sort((a, b) => b.markets - a.markets).slice(0, 30),
  // Leagues inside each bucket, so a bucket median can be traced to the books that set it.
  bucketLeagues: Object.fromEntries(BUCKETS.map((k) => [k, Object.entries(Object.groupBy(priced.filter((p) => p.bucket === k), (p) => p.league))
    .map(([league, xs]) => ({ league, books: xs!.length, medianSpreadC: median(xs!.map((x) => x.spreadC)), medianUsd2c: Math.round(median(xs!.map((x) => x.usd2c))!) }))
    .sort((x, y) => y.books - x.books).slice(0, 8)])),
  soccerByBucket: BUCKETS.map((k) => {
    const xs = priced.filter((p) => p.bucket === k && p.soccer);
    return { bucket: k, books: xs.length, medianSpreadC: median(xs.map((x) => x.spreadC)), medianUsd2c: xs.length ? Math.round(median(xs.map((x) => x.usd2c))!) : null, medianUsd5c: xs.length ? Math.round(median(xs.map((x) => x.usd5c))!) : null };
  }),
  inPlayByLeague: Object.entries(Object.groupBy(priced.filter((p) => p.bucket === "in-play"), (p) => p.league))
    .map(([league, xs]) => ({ league, books: xs!.length, medianSpreadC: median(xs!.map((x) => x.spreadC)), medianUsd2c: Math.round(median(xs!.map((x) => x.usd2c))!) }))
    .sort((a, b) => b.books - a.books),
}, null, 1));
