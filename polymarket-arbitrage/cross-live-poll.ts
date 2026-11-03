// Watch the same soccer games on Polymarket and Kalshi through a live match. Every few seconds it
// reads every Polymarket YES book (public CLOB) and every Kalshi quote (public trade API) and logs,
// per game, the cost of one share of each outcome at the cheaper venue. It places no orders.
// The score comes from one 0xinsider live games list call every 30 s; a failed read keeps each game's
// last score and marks the line scoreStale. A game missing from the live list is "not-live". (An
// earlier revision read /games/{slug} per game and, on 2026-11-03, ran the API key's per-minute
// budget out and dropped whole polls with it.)
// Run: OXINSIDER_API_KEY=... node cross-live-poll.ts ucl-mnu-rom-2026-11-03=KXUCLGAME-26NOV03MUNROM [more pairs] > cross-live.jsonl
//      env EVERY_MS (default 10000) and UNTIL (ISO time, default three hours from now).
const API = "https://api.0xinsider.com/api/v1";
const CLOB = "https://clob.polymarket.com";
const KALSHI = "https://api.elections.kalshi.com/trade-api/v2";
const KEY = process.env.OXINSIDER_API_KEY;
if (!KEY) throw new Error("set OXINSIDER_API_KEY (a Pro or Max key)");
const EVERY_MS = Number(process.env.EVERY_MS ?? 10_000);
const UNTIL = Date.parse(process.env.UNTIL ?? new Date(Date.now() + 3 * 3600_000).toISOString());

type Side = "home" | "draw" | "away";
interface ListGame { event_slug: string; status: { state: string; ended: boolean }; competitors: { name: string; score?: string }[]; markets: { side: Side; outcome_token_ids: string[] }[] }
interface KalshiMarket { ticker: string; yes_sub_title: string; yes_ask_dollars: string; yes_bid_dollars: string; status: string }
interface Book { asset_id: string; bids: { price: string }[]; asks: { price: string }[] }

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
const STOP = new Set(["fc", "cf", "ac", "sc", "afc", "club", "de", "the", "cd", "sv", "fk", "sk", "vs"]);
const words = (name: string) =>
  name.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/[^a-z ]/g, " ").split(" ")
    .filter((w) => w.length >= 3 && !STOP.has(w)).map((w) => w.slice(0, 4));
const overlap = (a: string, b: string) => words(a).filter((w) => words(b).includes(w)).length;
const liveList = async () =>
  (await getJson<{ data: ListGame[] }>(`${API}/games?sport=soccer&status=live&limit=100`, { headers: { Authorization: `Bearer ${KEY}` } })).data;
const kalshiEvent = (ticker: string) => getJson<{ event: { markets: KalshiMarket[] } }>(`${KALSHI}/events/${ticker}?with_nested_markets=true`);

const first = await liveList();
const pairs = await Promise.all(process.argv.slice(2).map(async (arg) => {
  const [slug, ticker] = arg.split("=");
  if (!slug || !ticker) throw new Error(`pair ${arg}: want polymarketSlug=KALSHIEVENT`);
  const g = first.find((x) => x.event_slug === slug);
  if (!g) throw new Error(`${slug}: not in the live games list`);
  const k = (await kalshiEvent(ticker)).event.markets;
  const legs = (["home", "draw", "away"] as const).map((side) => {
    const pm = g.markets.find((m) => m.side === side);
    const km = side === "draw" ? k.find((m) => m.yes_sub_title === "Tie")
      : k.find((m) => m.yes_sub_title !== "Tie" && overlap(m.yes_sub_title, g.competitors[side === "home" ? 0 : 1]!.name) > 0);
    if (!pm || !km) throw new Error(`${slug}: no ${side} leg on both venues`);
    return { side, yes: pm.outcome_token_ids[0]!, kalshi: km.ticker };
  });
  return { slug, ticker, legs, state: g.status.state, score: "" };
}));

let lastScoreRead = 0;
let scoreStale = false;
while (Date.now() < UNTIL) {
  const started = Date.now();
  try {
    if (started - lastScoreRead >= 30_000) {
      lastScoreRead = started;
      try {
        const list = await liveList();
        for (const p of pairs) {
          const g = list.find((x) => x.event_slug === p.slug);
          if (!g) { p.state = "not-live"; continue; }
          p.state = g.status.ended ? "ended" : g.status.state;
          p.score = g.competitors.map((c) => c.score ?? "").join("-");
        }
        scoreStale = false;
      } catch (err) {
        scoreStale = true;
        console.error(JSON.stringify({ at: new Date().toISOString(), error: String(err) }));
      }
    }
    // Both venues at once, so the two reads land as close together as the network allows; each line
    // records when each venue's read finished.
    const body = JSON.stringify(pairs.flatMap((p) => p.legs.map((l) => ({ token_id: l.yes }))));
    let kalshiAt = "";
    let pmAt = "";
    const [events, bookList] = await Promise.all([
      Promise.all(pairs.map((p) => kalshiEvent(p.ticker))).then((r) => { kalshiAt = new Date().toISOString(); return r; }),
      getJson<Book[]>(`${CLOB}/books`, { method: "POST", body, headers: { "Content-Type": "application/json" } }).then((r) => { pmAt = new Date().toISOString(); return r; }),
    ]);
    const kalshi = new Map<string, KalshiMarket>(events.flatMap((e) => e.event.markets.map((m) => [m.ticker, m] as const)));
    const books = new Map(bookList.map((b) => [b.asset_id, b]));
    for (const p of pairs) {
      const legs = p.legs.map((l) => {
        const b = books.get(l.yes);
        const k = kalshi.get(l.kalshi);
        return {
          pmAsk: b && b.asks.length ? Math.min(...b.asks.map((a) => Number(a.price))) : null,
          pmBid: b && b.bids.length ? Math.max(...b.bids.map((a) => Number(a.price))) : null,
          kAsk: k && k.status === "active" && Number(k.yes_ask_dollars) > 0 ? Number(k.yes_ask_dollars) : null,
          kBid: k && k.status === "active" ? Number(k.yes_bid_dollars) : null,
        };
      });
      const both = legs.every((l) => l.pmAsk !== null && l.kAsk !== null);
      console.log(JSON.stringify({
        kalshiAt, pmAt, slug: p.slug, state: p.state, score: p.score, ...(scoreStale ? { scoreStale } : {}), legs,
        crossSumAsks: both ? Number(legs.reduce((x, l) => x + Math.min(l.pmAsk!, l.kAsk!), 0).toFixed(4)) : null,
        pmSumAsks: legs.every((l) => l.pmAsk !== null) ? Number(legs.reduce((x, l) => x + l.pmAsk!, 0).toFixed(4)) : null,
        kalshiSumAsks: legs.every((l) => l.kAsk !== null) ? Number(legs.reduce((x, l) => x + l.kAsk!, 0).toFixed(4)) : null,
      }));
    }
  } catch (err) {
    // A failed poll is reported and skipped, so one timeout does not end the watch.
    console.error(JSON.stringify({ at: new Date().toISOString(), error: String(err) }));
  }
  await new Promise((r) => setTimeout(r, Math.max(0, EVERY_MS - (Date.now() - started))));
}
