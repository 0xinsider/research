// Do price jumps on Polymarket sports moneylines hold, or snap back, before and during the game?
// Pages Gamma's sports events that closed in the last HOURS (default 24), keeps the moneylines of
// games with at least MIN_VOLUME traded in their last day, and reads one-minute CLOB price history
// for each Yes token from six hours before the start to the close. A jump is a move of 5 cents or
// more within 5 minutes, with the price between 5 and 95 cents; the series then skips 5 minutes.
// Pregame is before Gamma's gameStartTime, in-play from it to 15 minutes before the market closed.
// For each jump: did the next minute take back at least half of it, and how much of it was still
// there 60 minutes later. Public data, no key.
// Run: node move-study.ts > move-study.json   (env HOURS, MIN_VOLUME)
const GAMMA = "https://gamma-api.polymarket.com";
const CLOB = "https://clob.polymarket.com";
const HOURS = Number(process.env.HOURS ?? 24);
const MIN_VOLUME = Number(process.env.MIN_VOLUME ?? 5000);
const JUMP = 0.05;
const WINDOW = 5;
const TAIL_MIN = 15;

interface Market { sportsMarketType?: string; gameStartTime?: string; closedTime?: string; clobTokenIds?: string }
interface Event { slug: string; closedTime?: string; volume24hr?: number | null; series?: { slug: string }[]; markets?: Market[] }

async function getJson<T>(url: string): Promise<T> {
  for (let attempt = 0; ; attempt++) {
    const res = await fetch(url);
    if ((res.status === 429 || res.status >= 500) && attempt < 5) {
      await new Promise((r) => setTimeout(r, 1000 * 2 ** attempt));
      continue;
    }
    if (!res.ok) throw new Error(`${res.status} ${url}: ${(await res.text()).slice(0, 200)}`);
    return (await res.json()) as T;
  }
}
const parseTs = (s: string) => Date.parse(s.replace(" ", "T").replace(/\+00(:00)*$/, "+00:00").replace(/(\.\d{3})\d+/, "$1"));

const now = Date.now();
const since = now - HOURS * 3_600_000;
const events: Event[] = [];
for (let offset = 0; ; offset += 100) {
  const q = new URLSearchParams({ tag_slug: "sports", closed: "true", order: "closedTime", ascending: "false", limit: "100", offset: String(offset) });
  const res = await fetch(`${GAMMA}/events?${q}`);
  if (res.status === 422) break;
  if (!res.ok) throw new Error(`${res.status} closed events offset ${offset}`);
  const page = (await res.json()) as Event[];
  if (page.length === 0) break;
  events.push(...page);
  if (Date.parse(page.at(-1)!.closedTime ?? "") < since) break;
}

const markets = events
  .filter((e) => e.closedTime && Date.parse(e.closedTime) >= since && (e.volume24hr ?? 0) >= MIN_VOLUME)
  .flatMap((e) => (e.markets ?? []).flatMap((m) => {
    if (m.sportsMarketType !== "moneyline" || !m.gameStartTime || !m.closedTime || !m.clobTokenIds) return [];
    const start = parseTs(m.gameStartTime);
    const close = parseTs(m.closedTime);
    // A game whose market closed before its listed start, or more than 8 hours after it, has a start
    // time that does not describe the game; it is left out.
    if (!(close > start) || close - start > 8 * 3_600_000) return [];
    return [{ event: e.slug, league: e.series?.[0]?.slug ?? "", token: (JSON.parse(m.clobTokenIds) as string[])[0]!, start, close }];
  }));

type Jump = { phase: "pregame" | "in-play"; event: string; league: string; size: number; reversedNextMinute: boolean; kept60: number | null };
const jumps: Jump[] = [];
let read = 0;
async function study(m: (typeof markets)[number]) {
  const q = new URLSearchParams({ market: m.token, startTs: String(Math.floor((m.start - 6 * 3_600_000) / 1000)), endTs: String(Math.floor(m.close / 1000)), fidelity: "1" });
  const { history } = await getJson<{ history: { t: number; p: number }[] }>(`${CLOB}/prices-history?${q}`);
  read++;
  const pts = history.map((h) => ({ t: h.t * 1000, p: h.p })).sort((a, b) => a.t - b.t);
  const at = (t: number) => {
    // The last point at or before t: the price a trader would have seen.
    let lo = 0, hi = pts.length - 1, found = -1;
    while (lo <= hi) { const mid = (lo + hi) >> 1; if (pts[mid]!.t <= t) { found = mid; lo = mid + 1; } else hi = mid - 1; }
    return found < 0 ? null : pts[found]!.p;
  };
  const end = m.close - TAIL_MIN * 60_000;
  for (let i = 0; i < pts.length; i++) {
    const cur = pts[i]!;
    if (cur.t >= end || cur.p < 0.05 || cur.p > 0.95) continue;
    const base = at(cur.t - WINDOW * 60_000);
    if (base === null || Math.abs(cur.p - base) < JUMP) continue;
    const move = cur.p - base;
    const next = at(cur.t + 60_000);
    const later = cur.t + 60 * 60_000 < end ? at(cur.t + 60 * 60_000) : null;
    jumps.push({
      phase: cur.t < m.start ? "pregame" : "in-play",
      event: m.event,
      league: m.league,
      size: Math.abs(move),
      reversedNextMinute: next !== null && Math.sign(move) * (next - cur.p) <= -Math.abs(move) / 2,
      kept60: later === null ? null : (later - base) / move,
    });
    // Skip ahead so one move is counted once.
    const skipTo = cur.t + WINDOW * 60_000;
    while (i + 1 < pts.length && pts[i + 1]!.t < skipTo) i++;
  }
}
const queue = [...markets];
await Promise.all(Array.from({ length: 6 }, async () => { for (let m = queue.shift(); m; m = queue.shift()) await study(m); }));

const median = (xs: number[]) => {
  const s = [...xs].sort((a, b) => a - b);
  return s.length === 0 ? null : s.length % 2 ? s[(s.length - 1) / 2]! : (s[s.length / 2 - 1]! + s[s.length / 2]!) / 2;
};
const summary = (["pregame", "in-play"] as const).map((phase) => {
  const js = jumps.filter((j) => j.phase === phase);
  const kept = js.map((j) => j.kept60).filter((k) => k !== null);
  return {
    phase,
    jumps: js.length,
    games: new Set(js.map((j) => j.event)).size,
    medianSizeC: Number(((median(js.map((j) => j.size)) ?? 0) * 100).toFixed(1)),
    reversedNextMinutePct: js.length ? Number(((100 * js.filter((j) => j.reversedNextMinute).length) / js.length).toFixed(1)) : null,
    with60: kept.length,
    medianKept60: kept.length ? Number(median(kept)!.toFixed(2)) : null,
    keptHalfPct: kept.length ? Number(((100 * kept.filter((k) => k >= 0.5).length) / kept.length).toFixed(1)) : null,
    reversedFullyPct: kept.length ? Number(((100 * kept.filter((k) => k <= 0).length) / kept.length).toFixed(1)) : null,
  };
});
console.log(JSON.stringify({
  readAt: new Date(now).toISOString(),
  windowStart: new Date(since).toISOString(),
  closedEvents: events.filter((e) => e.closedTime && Date.parse(e.closedTime) >= since).length,
  marketsStudied: markets.length,
  historiesRead: read,
  summary,
  byLeague: Object.entries(Object.groupBy(jumps, (j) => `${j.league}|${j.phase}`)).map(([k, js]) => ({ league: k.split("|")[0], phase: k.split("|")[1], jumps: js!.length, reversedNextMinutePct: Number(((100 * js!.filter((j) => j.reversedNextMinute).length) / js!.length).toFixed(1)) }))
    .sort((a, b) => b.jumps - a.jumps).slice(0, 20),
}, null, 1));
