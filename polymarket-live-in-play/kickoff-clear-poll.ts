// Polymarket's docs say resting limit orders on sports markets are cancelled once the game begins,
// clearing the book at the official start time. This watches moneyline books across their
// gameStartTime to see it: every EVERY_MS it reads each Yes book from the public CLOB and logs the
// resting dollars (price times size) on each side, the number of price levels, and the dollars
// within 2 cents of the midpoint. Public data, no key. It places no orders.
// Run: node kickoff-clear-poll.ts col1-dep-cdt-2026-11-03 [more event slugs] > kickoff.jsonl
//      env EVERY_MS (default 2000) and UNTIL (ISO time, default two hours from now).
const GAMMA = "https://gamma-api.polymarket.com";
const CLOB = "https://clob.polymarket.com";
const EVERY_MS = Number(process.env.EVERY_MS ?? 2000);
const UNTIL = Date.parse(process.env.UNTIL ?? new Date(Date.now() + 2 * 3600_000).toISOString());

interface Level { price: string; size: string }
interface Book { asset_id: string; bids: Level[]; asks: Level[] }
interface Market { sportsMarketType?: string; gameStartTime?: string; clobTokenIds?: string; groupItemTitle?: string; question?: string }

const books: { event: string; outcome: string; token: string; start: string }[] = [];
for (const slug of process.argv.slice(2)) {
  const [event] = (await (await fetch(`${GAMMA}/events?slug=${slug}`)).json()) as { markets: Market[] }[];
  if (!event) throw new Error(`no event ${slug}`);
  for (const m of event.markets.filter((x) => x.sportsMarketType === "moneyline" && x.clobTokenIds && x.gameStartTime)) {
    books.push({ event: slug, outcome: m.groupItemTitle || m.question || "", token: (JSON.parse(m.clobTokenIds!) as string[])[0]!, start: m.gameStartTime! });
  }
}
if (books.length === 0) throw new Error("no moneyline books");
const usd = (ls: Level[]) => ls.reduce((x, l) => x + Number(l.price) * Number(l.size), 0);

while (Date.now() < UNTIL) {
  const started = Date.now();
  try {
    const res = await fetch(`${CLOB}/books`, { method: "POST", body: JSON.stringify(books.map((b) => ({ token_id: b.token }))), headers: { "Content-Type": "application/json" } });
    if (!res.ok) throw new Error(`${res.status} books`);
    const byToken = new Map(((await res.json()) as Book[]).map((b) => [b.asset_id, b]));
    const at = new Date().toISOString();
    for (const b of books) {
      const book = byToken.get(b.token);
      if (!book) continue;
      const bid = book.bids.length ? Math.max(...book.bids.map((l) => Number(l.price))) : null;
      const ask = book.asks.length ? Math.min(...book.asks.map((l) => Number(l.price))) : null;
      const mid = bid !== null && ask !== null ? (bid + ask) / 2 : null;
      const near = mid === null ? null : usd([...book.bids, ...book.asks].filter((l) => Math.abs(Number(l.price) - mid) <= 0.02 + 1e-9));
      console.log(JSON.stringify({
        at, event: b.event, outcome: b.outcome, start: b.start, bid, ask,
        bidLevels: book.bids.length, askLevels: book.asks.length,
        bidUsd: Math.round(usd(book.bids)), askUsd: Math.round(usd(book.asks)), usd2c: near === null ? null : Math.round(near),
      }));
    }
  } catch (err) {
    // A failed poll is reported and skipped, so one timeout does not end the watch.
    console.error(JSON.stringify({ at: new Date().toISOString(), error: String(err) }));
  }
  await new Promise((r) => setTimeout(r, Math.max(0, EVERY_MS - (Date.now() - started))));
}
