// The other side of a three-way set: a bot that already holds one Yes share of home, draw and away
// (minted for $1 by splitting and converting, or bought earlier) can sell all three into the bids.
// Every few seconds this reads Polymarket's public CLOB books for each listed game and logs the sale
// value of one set at the best bids and down the bid ladder for 100 and 1,000 shares, before and
// after the sports taker fee (shares x 0.05 x p x (1 - p), Polymarket trading/fees). It places no orders.
// The legs come from Gamma, read once at start: the moneyline markets <event>-<home>, <event>-draw and
// <event>-<away>, where the event slug is <league>-<home>-<away>-<date>. (The games API carries the same
// legs; Gamma is used here so this watcher spends none of the API key's per-minute budget, which the
// other watchers of the same night used up.)
// Run: node live-sale-poll.ts ucl-mnu-rom-2026-11-03 [more slugs] > sale.jsonl
//      env EVERY_MS (default 5000), UNTIL (ISO time, default two hours from now), FEE_RATE (0.05).
const GAMMA = "https://gamma-api.polymarket.com";
const CLOB = "https://clob.polymarket.com";
const EVERY_MS = Number(process.env.EVERY_MS ?? 5000);
const UNTIL = Date.parse(process.env.UNTIL ?? new Date(Date.now() + 2 * 3600_000).toISOString());
const FEE_RATE = Number(process.env.FEE_RATE ?? 0.05);
const SIZES = [100, 1000];

interface GammaEvent { markets: { slug: string; sportsMarketType?: string; clobTokenIds: string }[] }
interface Level { price: string; size: string }
interface Book { asset_id: string; bids: Level[]; asks: Level[] }

async function getJson<T>(url: string, init?: RequestInit): Promise<T> {
  for (let attempt = 0; ; attempt++) {
    const res = await fetch(url, init);
    if ((res.status === 429 || res.status >= 500) && attempt < 8) {
      // A 429 names its retry time in Retry-After; other failures back off from 1 second.
      const after = Number(res.headers.get("retry-after"));
      await new Promise((r) => setTimeout(r, after > 0 ? after * 1000 : 1000 * 2 ** Math.min(attempt, 4)));
      continue;
    }
    if (!res.ok) throw new Error(`${res.status} ${url}: ${(await res.text()).slice(0, 200)}`);
    return (await res.json()) as T;
  }
}

// Proceeds of selling `size` shares down the bid ladder, per share, before and after the taker fee;
// null when the bids hold fewer than `size` shares.
function salePerShare(bids: Level[], size: number): { gross: number; net: number } | null {
  let left = size;
  let gross = 0;
  let fee = 0;
  for (const level of [...bids].sort((a, b) => Number(b.price) - Number(a.price))) {
    const p = Number(level.price);
    const take = Math.min(left, Number(level.size));
    gross += take * p;
    fee += take * FEE_RATE * p * (1 - p);
    left -= take;
    if (left <= 0) return { gross: gross / size, net: (gross - fee) / size };
  }
  return null;
}
const r4 = (x: number) => Number(x.toFixed(4));

const sets: { slug: string; yes: string[] }[] = [];
for (const slug of process.argv.slice(2)) {
  const [, home, away] = slug.split("-");
  const [event] = await getJson<GammaEvent[]>(`${GAMMA}/events?slug=${slug}`);
  if (!event) throw new Error(`${slug}: no Gamma event`);
  const yes = [home, "draw", away].map((code) => {
    const m = event.markets.find((x) => x.slug === `${slug}-${code}` && x.sportsMarketType === "moneyline");
    if (!m) throw new Error(`${slug}: no ${code} moneyline`);
    return (JSON.parse(m.clobTokenIds) as string[])[0]!;
  });
  sets.push({ slug, yes });
}

while (Date.now() < UNTIL) {
  const started = Date.now();
  try {
    const tokens = sets.flatMap((s) => s.yes);
    const books: Book[] = [];
    for (let i = 0; i < tokens.length; i += 25) {
      const body = JSON.stringify(tokens.slice(i, i + 25).map((token_id) => ({ token_id })));
      books.push(...(await getJson<Book[]>(`${CLOB}/books`, { method: "POST", body, headers: { "Content-Type": "application/json" } })));
    }
    const byToken = new Map(books.map((b) => [b.asset_id, b]));
    const at = new Date().toISOString();
    for (const s of sets) {
      const legs = s.yes.map((t) => byToken.get(t));
      if (legs.some((b) => b === undefined || b.bids.length === 0)) continue;
      const best = legs.map((b) => [...b!.bids].sort((x, y) => Number(y.price) - Number(x.price))[0]!);
      const bids = best.map((l) => Number(l.price));
      const sumBids = bids.reduce((x, y) => x + y, 0);
      const fee = bids.reduce((x, p) => x + FEE_RATE * p * (1 - p), 0);
      const sale = Object.fromEntries(SIZES.map((size) => {
        const legsSale = legs.map((b) => salePerShare(b!.bids, size));
        if (legsSale.some((x) => x === null)) return [size, null];
        return [size, { gross: r4(legsSale.reduce((x, y) => x + y!.gross, 0)), net: r4(legsSale.reduce((x, y) => x + y!.net, 0)) }];
      }));
      console.log(JSON.stringify({
        at, slug: s.slug, bids, bidSizes: best.map((l) => Number(l.size)),
        sumBids: r4(sumBids), netAtBest: r4(sumBids - fee),
        // Shares a set sale at the best bids could fill: the smallest best-bid size of the three legs.
        setsAtBest: Math.min(...best.map((l) => Number(l.size))),
        sale,
      }));
    }
  } catch (err) {
    // A failed poll is reported and skipped, so one timeout does not end the watch.
    console.error(JSON.stringify({ at: new Date().toISOString(), error: String(err) }));
  }
  await new Promise((r) => setTimeout(r, Math.max(0, EVERY_MS - (Date.now() - started))));
}
