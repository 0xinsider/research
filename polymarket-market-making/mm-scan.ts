// Market-making scan of open Polymarket sports markets. Public data, read-only, places no orders.
// Input: the snapshot sports-universe.ts writes. Output (stdout, JSON):
//   1. spreads by sportsMarketType, by league, moneylines sports vs esports;
//   2. fee schedules, liquidity-reward settings, tick sizes and in-play delays as Gamma lists them,
//      and the sports markets the CLOB rewards program funds today;
//   3. CLOB order books of the top moneylines: spread and resting dollars within 2c and 5c of mid;
//   4. taker markouts at +1, +5 and +30 minutes on the busiest moneylines over the last 24 hours.
// Run: node sports-universe.ts > universe.json && node mm-scan.ts universe.json > mm-scan.json
import { readFileSync } from "node:fs";

const CLOB = "https://clob.polymarket.com";
const DATA = "https://data-api.polymarket.com";

interface Market {
  event: string;
  series: string | null;
  esports: boolean;
  slug: string;
  conditionId: string;
  tokens: string[];
  type: string | null;
  acceptingOrders: boolean;
  bestBid: number | null;
  bestAsk: number | null;
  volume24hr: number;
  liquidity: number;
  feeSchedule: { rate: number; exponent: number; takerOnly: boolean; rebateRate: number } | null;
  feeType: string | null;
  rewardsMaxSpread: number | null;
  rewardsMinSize: number | null;
  tick: number | null;
  minSize: number | null;
  secondsDelay: number | null;
  gameStartTime: string | null;
  outcomes: string[];
}
const snap = JSON.parse(readFileSync(process.argv[2] ?? "universe.json", "utf8")) as {
  readAt: string;
  events: number;
  stop: string;
  markets: Market[];
};

const quantile = (xs: number[], q: number) => {
  if (xs.length === 0) return null;
  const s = [...xs].sort((a, b) => a - b);
  const i = (s.length - 1) * q;
  const lo = Math.floor(i);
  const hi = Math.ceil(i);
  return s[lo]! + (s[hi]! - s[lo]!) * (i - lo);
};
const round = (x: number | null, d = 2) => (x === null ? null : Number(x.toFixed(d)));
const cents = (x: number) => Math.round(x * 1000) / 10; // a price gap in cents, 0.1c resolution
const tally = <T>(xs: T[], key: (x: T) => string) => {
  const out: Record<string, number> = {};
  for (const x of xs) out[key(x)] = (out[key(x)] ?? 0) + 1;
  return Object.fromEntries(Object.entries(out).sort((a, b) => b[1] - a[1]));
};

// A market is quoted when both sides of its book hold an order.
const live = snap.markets.filter((m) => m.acceptingOrders);
const quoted = (m: Market) => m.bestBid !== null && m.bestAsk !== null && m.bestBid > 0 && m.bestAsk < 1 && m.bestAsk > m.bestBid;
const spreadC = (m: Market) => cents(m.bestAsk! - m.bestBid!);

const spreadStats = (ms: Market[]) => {
  const q = ms.filter(quoted).map(spreadC);
  return {
    markets: ms.length,
    quoted: q.length,
    volume24hrUsd: Math.round(ms.reduce((s, m) => s + m.volume24hr, 0)),
    p25: round(quantile(q, 0.25), 1),
    median: round(quantile(q, 0.5), 1),
    p75: round(quantile(q, 0.75), 1),
    atOrUnder1cPct: q.length ? round((100 * q.filter((c) => c <= 1).length) / q.length, 1) : null,
  };
};

const byType = Object.entries(
  live.reduce<Record<string, Market[]>>((acc, m) => ((acc[m.type ?? "(none)"] ??= []).push(m), acc), {}),
)
  .map(([type, ms]) => ({ type, ...spreadStats(ms) }))
  .sort((a, b) => b.volume24hrUsd - a.volume24hrUsd);

const moneylines = live.filter((m) => m.type === "moneyline");
const bySeries = Object.entries(
  moneylines.reduce<Record<string, Market[]>>((acc, m) => ((acc[m.series ?? "(none)"] ??= []).push(m), acc), {}),
)
  .map(([series, ms]) => ({ series, esports: ms.some((m) => m.esports), ...spreadStats(ms) }))
  .sort((a, b) => b.volume24hrUsd - a.volume24hrUsd)
  .slice(0, 15);

const feeKey = (m: Market) =>
  m.feeSchedule
    ? `rate ${m.feeSchedule.rate} / rebate ${m.feeSchedule.rebateRate} / ${m.feeSchedule.takerOnly ? "taker only" : "both sides"} / exponent ${m.feeSchedule.exponent}`
    : "none";

// Order books: the 40 busiest sports moneylines and the 20 busiest esports moneylines, first outcome token.
const top = (ms: Market[], k: number) => [...ms].sort((a, b) => b.volume24hr - a.volume24hr).slice(0, k);
const bookSet = [...top(moneylines.filter((m) => !m.esports), 40), ...top(moneylines.filter((m) => m.esports), 20)];

interface Level { price: string; size: string }
interface Book { asset_id: string; bids: Level[]; asks: Level[]; tick_size: string; min_order_size: string; timestamp: string }
async function books(tokens: string[]): Promise<Map<string, Book>> {
  const out = new Map<string, Book>();
  for (let i = 0; i < tokens.length; i += 25) {
    const res = await fetch(`${CLOB}/books`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(tokens.slice(i, i + 25).map((token_id) => ({ token_id }))),
    });
    if (!res.ok) throw new Error(`POST /books ${res.status}: ${await res.text()}`);
    for (const b of (await res.json()) as Book[]) out.set(b.asset_id, b);
  }
  return out;
}
const bookRead = new Date().toISOString();
const bk = await books(bookSet.map((m) => m.tokens[0]!));
const bookRows = bookSet.flatMap((m) => {
  const b = bk.get(m.tokens[0]!);
  if (!b) return [];
  const bids = b.bids.map((l) => ({ p: Number(l.price), s: Number(l.size) }));
  const asks = b.asks.map((l) => ({ p: Number(l.price), s: Number(l.size) }));
  if (bids.length === 0 || asks.length === 0) return [];
  const bid = Math.max(...bids.map((l) => l.p));
  const ask = Math.min(...asks.map((l) => l.p));
  const mid = (bid + ask) / 2;
  const within = (band: number) =>
    Math.round([...bids, ...asks].filter((l) => Math.abs(l.p - mid) <= band + 1e-9).reduce((s, l) => s + l.p * l.s, 0));
  return [{
    market: m.slug,
    series: m.series,
    esports: m.esports,
    outcome: m.outcomes[0] ?? null,
    bid,
    ask,
    spreadC: cents(ask - bid),
    usdWithin2c: within(0.02),
    usdWithin5c: within(0.05),
    volume24hrUsd: Math.round(m.volume24hr),
    tick: Number(b.tick_size),
    gameStartTime: m.gameStartTime,
  }];
});
const bookSummary = (rows: typeof bookRows) => ({
  books: rows.length,
  medianSpreadC: round(quantile(rows.map((r) => r.spreadC), 0.5), 1),
  medianUsdWithin2c: Math.round(quantile(rows.map((r) => r.usdWithin2c), 0.5) ?? 0),
  medianUsdWithin5c: Math.round(quantile(rows.map((r) => r.usdWithin5c), 0.5) ?? 0),
  medianVolume24hrUsd: Math.round(quantile(rows.map((r) => r.volume24hrUsd), 0.5) ?? 0),
});

// Taker markouts. Data API /v2/trades serves each fill once, on its taker side. A trade in the
// second outcome token is the mirror trade in the first (buy token 2 at p = sell token 1 at 1 - p),
// so one minute-level price history of token 1 marks every fill. Markout = the later price minus
// the fill price, signed for the taker: positive means the taker gained and the maker lost.
interface Trade { side: "BUY" | "SELL"; token_id: string; size: number; price: number; timestamp: number }
const now = Math.floor(Date.now() / 1000);
const since = now - 24 * 3600;
async function trades(conditionId: string): Promise<Trade[]> {
  const out: Trade[] = [];
  let cursor: string | null = null;
  for (let page = 0; page < 10; page++) {
    const q = new URLSearchParams({ condition: conditionId, limit: "1000" });
    if (cursor) q.set("cursor", cursor);
    const res = await fetch(`${DATA}/v2/trades?${q}`);
    if (!res.ok) throw new Error(`/v2/trades ${res.status}`);
    const body = (await res.json()) as { data: Trade[]; pagination: { next_cursor: string | null } };
    out.push(...body.data.filter((t) => t.timestamp >= since));
    cursor = body.pagination.next_cursor;
    if (!cursor || body.data.some((t) => t.timestamp < since)) break;
  }
  return out;
}
async function history(token: string, start: number, end: number): Promise<{ t: number; p: number }[]> {
  const res = await fetch(`${CLOB}/prices-history?market=${token}&startTs=${start}&endTs=${end}&fidelity=1`);
  if (!res.ok) throw new Error(`/prices-history ${res.status}`);
  return ((await res.json()) as { history: { t: number; p: number }[] }).history;
}
const HORIZONS = [60, 300, 1800] as const;
// Mid between 10c and 90c, the band where Polymarket lets one-sided quotes score for rewards: near the
// bounds a cent is a large share of the price and markouts stop being comparable.
const midOf = (m: Market) => (quoted(m) ? (m.bestBid! + m.bestAsk!) / 2 : null);
const markoutSet = top(moneylines.filter((m) => { const mid = midOf(m); return mid !== null && mid >= 0.1 && mid <= 0.9; }), 40);
// The book's width when Gamma was read: a 1-cent book, or a wider one.
const width = (m: Market) => (!quoted(m) ? "no two-sided quote" : spreadC(m) <= 1 ? "1c book" : "wider than 1c");
type Fill = { market: string; width: string; size: string; phase: string; mo: (number | null)[] };
const fills: Fill[] = [];
for (const m of markoutSet) {
  const [t1, t2] = m.tokens;
  const ts = (await trades(m.conditionId)).filter((t) => t.token_id === t1 || t.token_id === t2);
  if (ts.length === 0) continue;
  const h = await history(t1!, Math.min(...ts.map((t) => t.timestamp)) - 60, now);
  const start = m.gameStartTime ? Date.parse(m.gameStartTime.replace(" ", "T").replace("+00", "Z")) / 1000 : null;
  for (const t of ts) {
    // Express the fill in token-1 terms.
    const buy1 = (t.token_id === t1) === (t.side === "BUY");
    const p1 = t.token_id === t1 ? t.price : 1 - t.price;
    const mo = HORIZONS.map((hz) => {
      const later = h.find((pt) => pt.t >= t.timestamp + hz);
      if (!later || later.t > t.timestamp + hz + 120) return null; // no price within 2 minutes of the horizon
      return (buy1 ? later.p - p1 : p1 - later.p) * 100;
    });
    const usd = t.size * t.price;
    const size = usd < 100 ? "<$100" : usd < 1000 ? "$100-1k" : usd < 10000 ? "$1k-10k" : "$10k+";
    const phase = start === null ? "unknown" : t.timestamp >= start ? "in-play" : "pregame";
    fills.push({ market: m.slug, width: width(m), size, phase, mo });
  }
}
const cell = (xs: Fill[]) => {
  const mean = (i: number) => {
    const v = xs.map((f) => f.mo[i]).filter((x): x is number => x !== null);
    return v.length ? round(v.reduce((s, x) => s + x, 0) / v.length, 2) : null;
  };
  const with30 = xs.filter((f) => f.mo[2] !== null);
  return {
    fills: xs.length,
    fillsWith30m: with30.length,
    markets: new Set(with30.map((f) => f.market)).size,
    markout1mC: mean(0),
    markout5mC: mean(1),
    markout30mC: mean(2),
  };
};
const markoutsByWidth = ["1c book", "wider than 1c"].map((w) => ({ width: w, ...cell(fills.filter((f) => f.width === w)) }));
const markouts = ["<$100", "$100-1k", "$1k-10k", "$10k+"].flatMap((size) =>
  ["pregame", "in-play"].map((phase) => ({ size, phase, ...cell(fills.filter((f) => f.size === size && f.phase === phase)) })),
);

// Liquidity rewards actually funded today: CLOB /rewards/markets/multi for the sports tag. Gamma's
// rewardsMaxSpread and rewardsMinSize say how an order qualifies; rewards_config says what a market pays.
// The collection lists unfunded markets too and pages on without end, so read it sorted by daily rate
// and stop at the first page that reaches an unfunded market.
interface RewardMarket { condition_id: string; rewards_config: { rate_per_day: number; start_date: string; end_date: string }[] | null }
const today = new Date().toISOString().slice(0, 10);
const rewardMarkets: { conditionId: string; ratePerDay: number }[] = [];
for (let cursor = ""; cursor !== "LTE="; ) {
  const q = new URLSearchParams({ tag_slug: "sports", order_by: "rate_per_day", position: "DESC", page_size: "500" });
  if (cursor) q.set("next_cursor", cursor);
  const res = await fetch(`${CLOB}/rewards/markets/multi?${q}`);
  if (!res.ok) throw new Error(`/rewards/markets/multi ${res.status}`);
  const page = (await res.json()) as { data: RewardMarket[]; next_cursor: string };
  for (const m of page.data) {
    const rate = (m.rewards_config ?? [])
      .filter((c) => c.start_date <= today && (c.end_date ?? "9999") >= today)
      .reduce((s, c) => s + c.rate_per_day, 0);
    rewardMarkets.push({ conditionId: m.condition_id, ratePerDay: rate });
  }
  if (page.data.length === 0 || page.next_cursor === cursor || rewardMarkets.at(-1)!.ratePerDay === 0) break;
  cursor = page.next_cursor;
}
const funded = rewardMarkets.filter((m) => m.ratePerDay > 0);
const fundedIds = new Set(funded.map((m) => m.conditionId));
const rateBands = tally(funded, (m) => (m.ratePerDay < 10 ? "under $10" : m.ratePerDay < 50 ? "$10-49" : m.ratePerDay < 100 ? "$50-99" : m.ratePerDay < 250 ? "$100-249" : "$250+"));
const rewards = {
  readAt: new Date().toISOString(),
  listed: rewardMarkets.length,
  funded: funded.length,
  dailyUsd: Math.round(funded.reduce((s, m) => s + m.ratePerDay, 0)),
  medianDailyUsd: round(quantile(funded.map((m) => m.ratePerDay), 0.5), 2),
  topDailyUsd: Math.max(0, ...funded.map((m) => m.ratePerDay)),
  rateBands,
  fundedByType: tally(live.filter((m) => fundedIds.has(m.conditionId)), (m) => m.type ?? "(none)"),
  liveMarketsFunded: live.filter((m) => fundedIds.has(m.conditionId)).length,
};

console.log(JSON.stringify({
  universe: { readAt: snap.readAt, events: snap.events, stop: snap.stop, markets: snap.markets.length, acceptingOrders: live.length },
  byType,
  moneylineSports: spreadStats(moneylines.filter((m) => !m.esports)),
  moneylineEsports: spreadStats(moneylines.filter((m) => m.esports)),
  bySeries,
  feeSchedules: tally(live, feeKey),
  feeTypes: tally(live, (m) => m.feeType ?? "none"),
  rewardsMaxSpread: tally(live, (m) => String(m.rewardsMaxSpread)),
  rewardsMinSize: tally(live, (m) => String(m.rewardsMinSize)),
  tickSize: tally(live, (m) => String(m.tick)),
  orderMinSize: tally(live, (m) => String(m.minSize)),
  secondsDelay: tally(live, (m) => String(m.secondsDelay)),
  rewards,
  books: { readAt: bookRead, sports: bookSummary(bookRows.filter((r) => !r.esports)), esports: bookSummary(bookRows.filter((r) => r.esports)), rows: bookRows },
  markouts: { readAt: new Date().toISOString(), windowStart: new Date(since * 1000).toISOString(), markets: markoutSet.length, fills: fills.length, byWidth: markoutsByWidth, bySizeAndPhase: markouts },
}, null, 1));
