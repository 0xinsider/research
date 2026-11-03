// Watch the moneyline books of a list of games from kickoff to the final whistle. Every EVERY_MS it
// reads every listed game's state, clock and score from one 0xinsider live games list call, every Yes book from
// Polymarket's public CLOB, and, every fifth poll, each market's secondsDelay from Gamma. One JSON
// line per market per poll: spread, dollars resting within 2 and 5 cents of the midpoint, the delay.
// It places no orders. A failed list read keeps each game's last state and marks the line
// scoreStale, so the books are still logged; a game missing from the live list is logged as
// "not-live" (finished, or not live yet). One list call a poll keeps the API key's per-minute budget
// free for other work; an earlier revision read /games/{slug} per game and ran out of it on 2026-11-03.
// Run: OXINSIDER_API_KEY=... node depth-live-poll.ts ucl-mnu-rom-2026-11-03 [more slugs] > depth-live.jsonl
//      env EVERY_MS (default 30000) and UNTIL (ISO time, default three hours from now).
const API = "https://api.0xinsider.com/api/v1";
const CLOB = "https://clob.polymarket.com";
const GAMMA = "https://gamma-api.polymarket.com";
const KEY = process.env.OXINSIDER_API_KEY;
if (!KEY) throw new Error("set OXINSIDER_API_KEY (a Pro or Max key)");
const EVERY_MS = Number(process.env.EVERY_MS ?? 30_000);
const UNTIL = Date.parse(process.env.UNTIL ?? new Date(Date.now() + 3 * 3600_000).toISOString());

interface ListGame {
    event_slug: string;
    status: { state: string; period?: string; clock?: string; ended: boolean };
    competitors: { score?: string }[];
    markets: { condition_id: string; side: "home" | "draw" | "away"; outcome_token_ids: string[] }[];
}
interface Level { price: string; size: string }
interface Book { asset_id: string; bids: Level[]; asks: Level[] }

async function getJson<T>(url: string, init?: RequestInit): Promise<T> {
  for (let attempt = 0; ; attempt++) {
    const res = await fetch(url, init);
    if ((res.status === 429 || res.status >= 500) && attempt < 4) {
      // A 429 names its retry time in Retry-After; other failures back off from 1 second.
      const after = Number(res.headers.get("retry-after"));
      await new Promise((r) => setTimeout(r, after > 0 ? after * 1000 : 1000 * 2 ** attempt));
      continue;
    }
    if (!res.ok) throw new Error(`${res.status} ${url}: ${(await res.text()).slice(0, 200)}`);
    return (await res.json()) as T;
  }
}
const liveList = async () =>
  (await getJson<{ data: ListGame[] }>(`${API}/games?sport=soccer&status=live&limit=100`, { headers: { Authorization: `Bearer ${KEY}` } })).data;
// Dollars resting within `band` of the midpoint, both sides: price times size.
const near = (b: Book, mid: number, band: number) =>
  [...b.bids, ...b.asks].filter((l) => Math.abs(Number(l.price) - mid) <= band + 1e-9).reduce((x, l) => x + Number(l.price) * Number(l.size), 0);

const slugs = process.argv.slice(2);
const first = await liveList();
const games = slugs.map((slug) => {
  const g = first.find((x) => x.event_slug === slug);
  if (!g) throw new Error(`${slug}: not in the live games list`);
  return { slug, legs: g.markets.map((m) => ({ side: m.side, condition: m.condition_id, yes: m.outcome_token_ids[0]! })), state: "", clock: "", score: "" };
});
let scoreStale = false;
const delay = new Map<string, number | null>();

for (let poll = 0; Date.now() < UNTIL; poll++) {
  const started = Date.now();
  try {
    try {
      const list = await liveList();
      for (const g of games) {
        const d = list.find((x) => x.event_slug === g.slug);
        if (!d) { g.state = "not-live"; continue; }
        g.state = d.status.ended ? "ended" : d.status.state;
        g.clock = [d.status.period, d.status.clock].filter(Boolean).join(" ");
        g.score = d.competitors.map((c) => c.score ?? "").join("-");
      }
      scoreStale = false;
    } catch (err) {
      scoreStale = true;
      console.error(JSON.stringify({ at: new Date().toISOString(), error: String(err) }));
    }
    if (poll % 5 === 0) {
      const conditions = games.flatMap((g) => g.legs.map((l) => l.condition));
      for (let i = 0; i < conditions.length; i += 50) {
        const q = new URLSearchParams({ limit: "50" });
        for (const c of conditions.slice(i, i + 50)) q.append("condition_ids", c);
        for (const m of await getJson<{ conditionId: string; secondsDelay?: number | null }[]>(`${GAMMA}/markets?${q}`)) delay.set(m.conditionId, m.secondsDelay ?? null);
      }
    }
    const tokens = games.flatMap((g) => g.legs.map((l) => l.yes));
    const books = new Map<string, Book>();
    for (let i = 0; i < tokens.length; i += 25) {
      const body = JSON.stringify(tokens.slice(i, i + 25).map((token_id) => ({ token_id })));
      for (const b of await getJson<Book[]>(`${CLOB}/books`, { method: "POST", body, headers: { "Content-Type": "application/json" } })) books.set(b.asset_id, b);
    }
    const at = new Date().toISOString();
    for (const g of games) {
      for (const l of g.legs) {
        const b = books.get(l.yes);
        if (!b || b.bids.length === 0 || b.asks.length === 0) {
          console.log(JSON.stringify({ at, slug: g.slug, side: l.side, state: g.state, clock: g.clock, score: g.score, ...(scoreStale ? { scoreStale } : {}), oneSided: true, delay: delay.get(l.condition) ?? null }));
          continue;
        }
        const bid = Math.max(...b.bids.map((x) => Number(x.price)));
        const ask = Math.min(...b.asks.map((x) => Number(x.price)));
        const mid = (bid + ask) / 2;
        console.log(JSON.stringify({
          at, slug: g.slug, side: l.side, state: g.state, clock: g.clock, score: g.score, ...(scoreStale ? { scoreStale } : {}), bid, ask,
          spreadC: Number(((ask - bid) * 100).toFixed(2)), usd2c: Math.round(near(b, mid, 0.02)), usd5c: Math.round(near(b, mid, 0.05)),
          delay: delay.get(l.condition) ?? null,
        }));
      }
    }
  } catch (err) {
    // A failed poll is reported and skipped, so one timeout does not end the watch.
    console.error(JSON.stringify({ at: new Date().toISOString(), error: String(err) }));
  }
  await new Promise((r) => setTimeout(r, Math.max(0, EVERY_MS - (Date.now() - started))));
}
