// Who moves the price after a large trade, by the wallet's grade at the trade.
// Reads 0xinsider's large-trade feed (/api/v1/large-trades, filtered by condition_id) for the
// 40 busiest open sports moneylines in a sports-universe.ts snapshot, then marks each trade
// against Polymarket's public minute price history 30 minutes later.
// The last block is the kill switch itself: pull your quotes when a graded wallet trades size.
// Run: OXINSIDER_API_KEY=... node kill-switch.ts universe.json > kill-switch.json
import { readFileSync } from "node:fs";

const API = "https://api.0xinsider.com/api/v1";
const CLOB = "https://clob.polymarket.com";
const KEY = process.env.OXINSIDER_API_KEY;
if (!KEY) throw new Error("set OXINSIDER_API_KEY (a Pro or Max key)");

interface LargeTrade {
  id: string;
  traded_at: string;
  size_usd: number;
  side: "BUY" | "SELL";
  token_id: string;
  price: number;
  trader: { grade_at_trade: string | null };
  market: { condition_id: string; slug: string };
}
async function oxi<T>(path: string): Promise<T> {
  for (let attempt = 0; ; attempt++) {
    const res = await fetch(`${API}${path}`, { headers: { Authorization: `Bearer ${KEY}` } });
    if ((res.status === 429 || res.status === 503) && attempt < 4) {
      await new Promise((r) => setTimeout(r, 1000 * Number(res.headers.get("retry-after") ?? 2 ** attempt)));
      continue;
    }
    if (!res.ok) throw new Error(`${res.status} ${path}: ${await res.text()}`);
    return (await res.json()) as T;
  }
}

// The same 40 markets mm-scan.ts marks: open moneylines by 24h volume with a two-sided mid from 10c to 90c.
const snap = JSON.parse(readFileSync(process.argv[2] ?? "universe.json", "utf8")) as {
  readAt: string;
  markets: { slug: string; conditionId: string; type: string | null; acceptingOrders: boolean; bestBid: number | null; bestAsk: number | null; volume24hr: number; gameStartTime: string | null }[];
};
const markets = snap.markets
  .filter((m) => m.acceptingOrders && m.type === "moneyline")
  .filter((m) => {
    if (m.bestBid === null || m.bestAsk === null || !(m.bestBid > 0 && m.bestAsk < 1 && m.bestAsk > m.bestBid)) return false;
    const mid = (m.bestBid + m.bestAsk) / 2;
    return mid >= 0.1 && mid <= 0.9;
  })
  .sort((a, b) => b.volume24hr - a.volume24hr)
  .slice(0, 40);

const now = Math.floor(Date.now() / 1000);
const since = now - 24 * 3600;
const historyCache = new Map<string, { t: number; p: number }[]>();
async function priceAt(token: string, ts: number): Promise<number | null> {
  if (!historyCache.has(token)) {
    const res = await fetch(`${CLOB}/prices-history?market=${token}&startTs=${since - 60}&endTs=${now}&fidelity=1`);
    if (!res.ok) throw new Error(`/prices-history ${res.status}`);
    historyCache.set(token, ((await res.json()) as { history: { t: number; p: number }[] }).history);
  }
  const later = historyCache.get(token)!.find((pt) => pt.t >= ts);
  return later && later.t <= ts + 120 ? later.p : null;
}

const bucket = (g: string | null) => (g === "S" || g === "A" ? "S/A" : g === "B" || g === "C" ? "B/C" : g === "D" || g === "F" ? "D/F" : "ungraded");
const rows: { grade: string; phase: string; usd: number; markout30mC: number | null }[] = [];
for (const m of markets) {
  const start = m.gameStartTime ? Date.parse(m.gameStartTime.replace(" ", "T").replace("+00", "Z")) / 1000 : null;
  let cursor: string | null = null;
  for (let page = 0; page < 20; page++) {
    const q = new URLSearchParams({ condition_id: m.conditionId, sort: "recent", limit: "100" });
    if (cursor) q.set("cursor", cursor);
    const body = await oxi<{ data: LargeTrade[]; has_more: boolean; next_cursor: string | null }>(`/large-trades?${q}`);
    let older = false;
    for (const t of body.data) {
      const ts = Date.parse(t.traded_at) / 1000;
      if (ts < since) {
        older = true;
        continue;
      }
      const later = ts + 1800 <= now ? await priceAt(t.token_id, ts + 1800) : null;
      const markout = later === null ? null : (t.side === "BUY" ? later - t.price : t.price - later) * 100;
      rows.push({ grade: bucket(t.trader.grade_at_trade), phase: start !== null && ts >= start ? "in-play" : "pregame", usd: t.size_usd, markout30mC: markout });
    }
    cursor = body.next_cursor;
    if (older || !body.has_more || !cursor) break;
  }
}

const summary = ["S/A", "B/C", "D/F", "ungraded"].flatMap((grade) =>
  ["pregame", "in-play"].map((phase) => {
    const xs = rows.filter((r) => r.grade === grade && r.phase === phase);
    const marked = xs.filter((r) => r.markout30mC !== null);
    const mean = marked.length ? marked.reduce((s, r) => s + r.markout30mC!, 0) / marked.length : null;
    return {
      grade,
      phase,
      trades: xs.length,
      usd: Math.round(xs.reduce((s, r) => s + r.usd, 0)),
      marked: marked.length,
      markout30mC: mean === null ? null : Number(mean.toFixed(2)),
      movedTheirWayPct: marked.length ? Number(((100 * marked.filter((r) => r.markout30mC! > 0).length) / marked.length).toFixed(1)) : null,
    };
  }),
);
console.log(JSON.stringify({ readAt: new Date().toISOString(), universeReadAt: snap.readAt, windowStart: new Date(since * 1000).toISOString(), markets: markets.length, trades: rows.length, summary }, null, 1));

// The kill switch. Poll the markets you quote; on a fresh trade of $10,000 or more (the large-trade feed
// records fills from $10,000 up, so a lower min_size finds nothing more) by a wallet graded S or A at the
// trade, pull quotes. min_grade_at_trade is the grade the study above buckets by; min_grade would read the
// wallet's grade now, which can have moved since the fill.
// pullQuotes is yours to write against your own Polymarket client's cancel call.
export async function watch(conditionIds: string[], pullQuotes: (t: LargeTrade) => void, everyMs = 10_000) {
  const seen = new Set<string>();
  // Only trades after the watcher starts count: the feed returns market history, and an old trade
  // must not cancel quotes you place now.
  const startedAt = Date.now();
  for (;;) {
    for (const cid of conditionIds) {
      const q = new URLSearchParams({ condition_id: cid, min_grade_at_trade: "A", min_size: "10000", sort: "recent", limit: "20" });
      for (const t of (await oxi<{ data: LargeTrade[] }>(`/large-trades?${q}`)).data) {
        if (!seen.has(t.id)) {
          seen.add(t.id);
          if (Date.parse(t.traded_at) >= startedAt) pullQuotes(t);
        }
      }
    }
    await new Promise((r) => setTimeout(r, everyMs));
  }
}
