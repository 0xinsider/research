// When does each source show a goal? Every EVERY_MS this reads the score of each listed game from
// Polymarket's Gamma event (`score`) and from the 0xinsider live games list, and logs a line whenever
// either source's score for a game changes, with the read time and, for 0xinsider, its own
// `freshness.scores_observed_at`. It places no orders.
// Run: OXINSIDER_API_KEY=... node score-race-poll.ts ucl-mnu-rom-2026-11-03 [more slugs] > race.jsonl
//      env EVERY_MS (default 5000) and UNTIL (ISO time, default two hours from now).
const API = "https://api.0xinsider.com/api/v1";
const GAMMA = "https://gamma-api.polymarket.com";
const KEY = process.env.OXINSIDER_API_KEY;
if (!KEY) throw new Error("set OXINSIDER_API_KEY (a Pro or Max key)");
const EVERY_MS = Number(process.env.EVERY_MS ?? 5000);
const UNTIL = Date.parse(process.env.UNTIL ?? new Date(Date.now() + 2 * 3600_000).toISOString());
const slugs = process.argv.slice(2);

interface ListGame { event_slug: string; status: { state: string; clock?: string }; competitors: { score?: string }[]; freshness?: { scores_observed_at?: string } }
const last = new Map<string, string>();
const note = (source: string, slug: string, score: string, extra: Record<string, unknown>) => {
  const k = `${source}|${slug}`;
  if (last.get(k) === score) return;
  last.set(k, score);
  console.log(JSON.stringify({ at: new Date().toISOString(), source, slug, score, ...extra }));
};

while (Date.now() < UNTIL) {
  const started = Date.now();
  try {
    await Promise.all([
      ...slugs.map(async (slug) => {
        const res = await fetch(`${GAMMA}/events?slug=${slug}`);
        if (!res.ok) throw new Error(`${res.status} gamma ${slug}`);
        const [e] = (await res.json()) as { score?: string; period?: string; elapsed?: string }[];
        if (e?.score) note("gamma", slug, e.score.replace(/\s/g, ""), { period: e.period, elapsed: e.elapsed });
      }),
      (async () => {
        const res = await fetch(`${API}/games?sport=soccer&status=live&limit=100`, { headers: { Authorization: `Bearer ${KEY}` } });
        if (!res.ok) throw new Error(`${res.status} 0xinsider games`);
        const { data } = (await res.json()) as { data: ListGame[] };
        for (const g of data.filter((x) => slugs.includes(x.event_slug))) {
          note("0xinsider", g.event_slug, g.competitors.map((c) => c.score ?? "").join("-"), { clock: g.status.clock, scoresObservedAt: g.freshness?.scores_observed_at });
        }
      })(),
    ]);
  } catch (err) {
    // A failed poll is reported and skipped, so one timeout does not end the watch.
    console.error(JSON.stringify({ at: new Date().toISOString(), error: String(err) }));
  }
  await new Promise((r) => setTimeout(r, Math.max(0, EVERY_MS - (Date.now() - started))));
}
