// Cross-venue three-way scan: the same soccer games on Polymarket and Kalshi, read within seconds.
// Polymarket legs come from the 0xinsider games API and their asks from the public CLOB books;
// Kalshi quotes come from its public trade API. For each matched game it asks whether buying
// every outcome at the cheaper venue costs less than $1, before fees and after Polymarket's taker fee.
// Kalshi's own taker fee is left at zero, so the after-fee cost is a floor: the real cost is higher.
// Each Kalshi series reports its fee type, which the output records.
// It places no orders on either venue.
// Run: OXINSIDER_API_KEY=... node cross-venue-scan.ts > cross-venue.json
const API = "https://api.0xinsider.com/api/v1";
const CLOB = "https://clob.polymarket.com";
const GAMMA = "https://gamma-api.polymarket.com";
const KALSHI = "https://api.elections.kalshi.com/trade-api/v2";
const KEY = process.env.OXINSIDER_API_KEY;
if (!KEY) throw new Error("set OXINSIDER_API_KEY (a Pro or Max key)");
const SERIES = [
  "KXUCLGAME", "KXUELGAME", "KXUECLGAME", "KXEPLGAME", "KXLALIGAGAME", "KXSERIEAGAME", "KXBUNDESLIGAGAME",
  "KXLIGUE1GAME", "KXEFLCHAMPIONSHIPGAME", "KXEREDIVISIEGAME", "KXLIGAPORTUGALGAME", "KXMLSGAME",
];

type Side = "home" | "draw" | "away";
interface GameRow {
  event_slug: string;
  league: string;
  scheduled_at: string;
  title: string;
  status: { state: string };
  competitors: { name: string }[];
  markets: { condition_id: string; side: Side; outcome_token_ids: string[] }[];
}
interface KalshiMarket { ticker: string; yes_sub_title: string; yes_ask_dollars: string; yes_bid_dollars: string; rules_primary: string; status: string }
interface KalshiEvent { event_ticker: string; title: string; markets: KalshiMarket[] }
interface KalshiSeries { series: { ticker: string; fee_type: string; fee_multiplier: number } }
interface Book { asset_id: string; bids: { price: string }[]; asks: { price: string }[] }

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

// Team names differ by venue ("Bodoe/Glimt", "Bodø/Glimt"): compare accent-free word stems.
const STOP = new Set(["fc", "cf", "ac", "sc", "afc", "club", "de", "the", "cd", "sv", "fk", "sk", "vs"]);
const words = (name: string) =>
  name.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/[^a-z ]/g, " ").split(" ")
    .filter((w) => w.length >= 3 && !STOP.has(w)).map((w) => w.slice(0, 4));
const overlap = (a: string, b: string) => words(a).filter((w) => words(b).includes(w)).length;

// 1. Polymarket: scheduled and live soccer games with three legs, from the 0xinsider API.
const games: GameRow[] = [];
for (const status of ["scheduled", "live"]) {
  let cursor: string | null = null;
  do {
    const q = new URLSearchParams({ sport: "soccer", status, limit: "100" });
    if (cursor) q.set("cursor", cursor);
    const page = await getJson<{ data: GameRow[]; has_more: boolean; next_cursor: string | null }>(`${API}/games?${q}`, { headers: { Authorization: `Bearer ${KEY}` } });
    games.push(...page.data);
    cursor = page.has_more ? page.next_cursor : null;
  } while (cursor);
}

// 2. Kalshi: open game events in the big soccer series.
const kalshi: (KalshiEvent & { series: string; date: string })[] = [];
const kalshiFees: Record<string, string> = {};
for (const series of SERIES) {
  const info = (await getJson<KalshiSeries>(`${KALSHI}/series/${series}`)).series;
  kalshiFees[series] = `${info.fee_type} x${String(info.fee_multiplier)}`;
  const page = await getJson<{ events: KalshiEvent[] }>(`${KALSHI}/events?series_ticker=${series}&status=open&with_nested_markets=true&limit=200`);
  for (const e of page.events) {
    const m = /-(\d\d)([A-Z]{3})(\d\d)/.exec(e.event_ticker);
    if (!m) continue;
    const month = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"].indexOf(m[2]!) + 1;
    kalshi.push({ ...e, series, date: `20${m[1]}-${String(month).padStart(2, "0")}-${m[3]}` });
  }
}

// 3. Match on kickoff date (a day either way: venues date games in different zones) and both team names.
const day = (iso: string) => Date.parse(iso.slice(0, 10));
const matches = kalshi.flatMap((k) => {
  const [kHome, kAway] = k.title.split(" vs ");
  if (!kHome || !kAway || k.markets.length !== 3) return [];
  const candidates = games.filter((g) => Math.abs(day(g.scheduled_at) - day(k.date)) <= 86_400_000 && g.competitors.length === 2
    && overlap(kHome, g.competitors[0]!.name) > 0 && overlap(kAway, g.competitors[1]!.name) > 0);
  if (candidates.length !== 1) return [];
  const g = candidates[0]!;
  const legs = (["home", "draw", "away"] as const).map((side) => {
    const pm = g.markets.filter((m) => m.side === side);
    const km = side === "draw" ? k.markets.filter((m) => m.yes_sub_title === "Tie")
      : k.markets.filter((m) => m.yes_sub_title !== "Tie" && overlap(m.yes_sub_title, g.competitors[side === "home" ? 0 : 1]!.name) > 0);
    return pm.length === 1 && km.length === 1 ? { side, pm: pm[0]!, kalshi: km[0]! } : null;
  });
  if (legs.some((l) => l === null)) return [];
  return [{ game: g, kalshiEvent: k.event_ticker, series: k.series, legs: legs.map((l) => l!) }];
});

// 4. Polymarket books and fee rates for the matched legs.
const tokens = matches.flatMap((m) => m.legs.map((l) => l.pm.outcome_token_ids[0]!));
const books = new Map<string, Book>();
for (let i = 0; i < tokens.length; i += 25) {
  const body = JSON.stringify(tokens.slice(i, i + 25).map((token_id) => ({ token_id })));
  for (const b of await getJson<Book[]>(`${CLOB}/books`, { method: "POST", body, headers: { "Content-Type": "application/json" } })) books.set(b.asset_id, b);
}
const rates = new Map<string, number>();
const conditions = matches.flatMap((m) => m.legs.map((l) => l.pm.condition_id));
for (let i = 0; i < conditions.length; i += 50) {
  const q = new URLSearchParams({ limit: "50" });
  for (const c of conditions.slice(i, i + 50)) q.append("condition_ids", c);
  for (const m of await getJson<{ conditionId: string; feeSchedule?: { rate: number } | null }[]>(`${GAMMA}/markets?${q}`)) rates.set(m.conditionId, m.feeSchedule?.rate ?? 0);
}

const r4 = (x: number) => Number(x.toFixed(4));
const rows = matches.flatMap((m) => {
  const legs = m.legs.map((l) => {
    const book = books.get(l.pm.outcome_token_ids[0]!);
    const pmAsk = book && book.asks.length ? Math.min(...book.asks.map((a) => Number(a.price))) : null;
    const pmBid = book && book.bids.length ? Math.max(...book.bids.map((b) => Number(b.price))) : null;
    const kAsk = Number(l.kalshi.yes_ask_dollars);
    const kBid = Number(l.kalshi.yes_bid_dollars);
    const rate = rates.get(l.pm.condition_id) ?? 0;
    return { side: l.side, pmAsk, pmBid, kAsk, kBid, pmFee: pmAsk === null ? null : rate * pmAsk * (1 - pmAsk) };
  });
  if (legs.some((l) => l.pmAsk === null || l.pmBid === null || !(l.kAsk > 0))) return [];
  const pick = legs.map((l) => (l.pmAsk! <= l.kAsk ? "polymarket" : "kalshi"));
  const crossAsks = legs.reduce((x, l) => x + Math.min(l.pmAsk!, l.kAsk), 0);
  const crossFee = legs.reduce((x, l, i) => x + (pick[i] === "polymarket" ? l.pmFee! : 0), 0);
  // Cheapest after Polymarket's fee, leg by leg (Kalshi's fee at zero, so this is a floor).
  const crossAllIn = legs.reduce((x, l) => x + Math.min(l.pmAsk! + l.pmFee!, l.kAsk), 0);
  const crossBids = legs.reduce((x, l) => x + Math.max(l.pmBid!, l.kBid), 0);
  return [{
    event: m.game.event_slug, title: m.game.title, kalshi: m.kalshiEvent, series: m.series, kickoff: m.game.scheduled_at, state: m.game.status.state,
    legs: legs.map((l, i) => ({ side: l.side, pmAsk: l.pmAsk, pmBid: l.pmBid, kAsk: l.kAsk, kBid: l.kBid, cheaper: pick[i] })),
    pmSumAsks: r4(legs.reduce((x, l) => x + l.pmAsk!, 0)), kalshiSumAsks: r4(legs.reduce((x, l) => x + l.kAsk, 0)),
    crossSumAsks: r4(crossAsks), crossFee: r4(crossFee), crossAllIn: r4(crossAllIn), crossSumBids: r4(crossBids),
    midGapPts: r4(Math.max(...legs.map((l) => Math.abs((l.pmAsk! + l.pmBid!) / 2 - (l.kAsk + l.kBid) / 2))) * 100),
    kalshiRule: m.legs[0]!.kalshi.rules_primary,
  }];
});

const sorted = (xs: number[]) => [...xs].sort((a, b) => a - b);
const median = (xs: number[]) => { const s = sorted(xs); return s.length === 0 ? null : s.length % 2 ? s[(s.length - 1) / 2]! : (s[s.length / 2 - 1]! + s[s.length / 2]!) / 2; };
const count = (xs: number[], f: (x: number) => boolean) => xs.filter(f).length;
console.log(JSON.stringify({
  readAt: new Date().toISOString(),
  polymarketGames: games.length,
  kalshiEvents: kalshi.length,
  kalshiFeeTypes: kalshiFees,
  matched: matches.length,
  priced: rows.length,
  bySeries: Object.fromEntries(SERIES.map((s) => [s, rows.filter((r) => r.series === s).length]).filter(([, n]) => n !== 0)),
  pmSumAsks: { median: median(rows.map((r) => r.pmSumAsks)), min: Math.min(...rows.map((r) => r.pmSumAsks)) },
  kalshiSumAsks: { median: median(rows.map((r) => r.kalshiSumAsks)), min: Math.min(...rows.map((r) => r.kalshiSumAsks)) },
  crossSumAsks: { median: median(rows.map((r) => r.crossSumAsks)), min: Math.min(...rows.map((r) => r.crossSumAsks)), below1: count(rows.map((r) => r.crossSumAsks), (x) => x < 1), at1: count(rows.map((r) => r.crossSumAsks), (x) => Math.abs(x - 1) < 1e-9) },
  crossAllIn: { median: median(rows.map((r) => r.crossAllIn)), min: Math.min(...rows.map((r) => r.crossAllIn)), below1: count(rows.map((r) => r.crossAllIn), (x) => x < 1) },
  crossSumBids: { median: median(rows.map((r) => r.crossSumBids)), max: Math.max(...rows.map((r) => r.crossSumBids)), above1: count(rows.map((r) => r.crossSumBids), (x) => x > 1) },
  midGapPts: { median: median(rows.map((r) => r.midGapPts)), max: Math.max(...rows.map((r) => r.midGapPts)), within1: count(rows.map((r) => r.midGapPts), (x) => x <= 1 + 1e-9) },
  splitLegs: count(rows.map((r) => new Set(r.legs.map((l) => l.cheaper)).size), (x) => x > 1),
  cheapest: [...rows].sort((a, b) => a.crossSumAsks - b.crossSumAsks).slice(0, 8),
  rows,
}, null, 1));
