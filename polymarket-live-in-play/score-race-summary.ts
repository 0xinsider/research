// Who shows a goal first: the order book, Polymarket's Gamma score, or the 0xinsider games API?
// Reads score-race-poll.ts output (each source's score changes, 10-second polls) and its error log, and
// the book polls: live-arb-poll.ts output (Yes asks of home, draw and away every 5 seconds, the
// Champions League games) and depth-live-poll.ts output (each side's Yes book every 30 seconds, all
// games). For each game the 5-second polls are used where they exist.
// For each one-goal score change it takes the first time each source showed the new score, and the
// time the book moved: the earliest 5-second poll from which the scoring side's Yes ask stayed 5 cents
// or more above its level 5 minutes before the first source showed the goal. A change is left out
// when a source's read was failing (an error line) between the goal's first sighting and that
// source's own, because then that source's time measures the failure, not the feed. The book time is
// left out when the game's previous goal was first seen less than 5 minutes earlier, because the
// look-back would start before that goal.
// Run: node score-race-summary.ts race.jsonl race.err live.jsonl depth-live.jsonl
import { readFileSync } from "node:fs";

interface Race { at: string; source: "gamma" | "0xinsider"; slug: string; score: string; scoresObservedAt?: string }
interface Live { at: string; slug: string; asks: (number | null)[] }
interface DepthLine { at: string; slug: string; side: "home" | "draw" | "away"; ask?: number }
const jsonl = <T,>(path: string) => readFileSync(path, "utf8").trim().split("\n").filter(Boolean).map((l) => JSON.parse(l) as T);
const race = jsonl<Race>(process.argv[2] ?? "race.jsonl");
const errors = jsonl<{ at: string; error: string }>(process.argv[3] ?? "race.err").map((e) => ({ t: Date.parse(e.at), ours: /0xinsider/.test(e.error) }));
const fast = process.argv[4] ? jsonl<Live>(process.argv[4]) : [];
// depth-live lines, one per side, folded into one line per game and poll.
const slow = new Map<string, Live>();
for (const d of process.argv[5] ? jsonl<DepthLine>(process.argv[5]) : []) {
  const k = `${d.slug}|${d.at}`;
  const l = slow.get(k) ?? { at: d.at, slug: d.slug, asks: [null, null, null] };
  l.asks[{ home: 0, draw: 1, away: 2 }[d.side]] = d.ask ?? null;
  slow.set(k, l);
}
const fastSlugs = new Set(fast.map((l) => l.slug));
const live = [...fast, ...[...slow.values()].filter((l) => !fastSlugs.has(l.slug))];
const bookEvery = (slug: string) => (fastSlugs.has(slug) ? 5 : 30);
const t = (iso: string) => Date.parse(iso);
const median = (xs: number[]) => {
  const s = [...xs].sort((a, b) => a - b);
  return s.length === 0 ? null : s.length % 2 ? s[(s.length - 1) / 2]! : (s[s.length / 2 - 1]! + s[s.length / 2]!) / 2;
};
const goalsOf = (score: string) => score.split("-").map(Number).reduce((a, b) => a + b, 0);
// Prices compare in whole hundredths of a cent, which every Polymarket tick converts to exactly: in
// floating point 0.97 - 0.92 is 0.04999999999999993, so a 5-cent move tested in dollars falls short.
const units = (price: number) => Math.round(price * 10_000);
const FIVE_CENTS = 500;

const rows = [];
for (const slug of [...new Set(race.map((r) => r.slug))]) {
  const bySource = (source: Race["source"]) => race.filter((r) => r.slug === slug && r.source === source);
  // The score each source started on, then every later one-goal change seen by either source.
  const changes = new Map<string, { from: string; gamma?: Race; ours?: Race }>();
  for (const source of ["gamma", "0xinsider"] as const) {
    const ls = bySource(source);
    for (let i = 1; i < ls.length; i++) {
      const [prev, cur] = [ls[i - 1]!, ls[i]!];
      if (goalsOf(cur.score) !== goalsOf(prev.score) + 1) continue;
      const c = changes.get(cur.score) ?? { from: prev.score };
      // The first sighting stands: a feed that rolls a score back and restores it shows it again later.
      if (source === "gamma") c.gamma ??= cur;
      else c.ours ??= cur;
      changes.set(cur.score, c);
    }
  }
  for (const [to, c] of changes) {
    const firstAt = Math.min(...[c.gamma, c.ours].flatMap((x) => (x ? [t(x.at)] : [])));
    const failed = (source: "gamma" | "0xinsider", seenAt: number | undefined) =>
      errors.some((e) => (source === "0xinsider" ? e.ours : !e.ours) && e.t >= firstAt - 10_000 && e.t <= (seenAt ?? firstAt + 900_000));
    const [h0] = c.from.split("-").map(Number) as [number, number];
    const [h1] = to.split("-").map(Number) as [number, number];
    const leg = h1 > h0 ? 0 : 2;
    const prevGoalAt = Math.max(-Infinity, ...[...changes.values()].flatMap((o) => [o.gamma, o.ours]).flatMap((x) => (x && goalsOf(x.score) < goalsOf(to) ? [t(x.at)] : [])));
    let bookAt: number | null = null;
    const ls = live.filter((l) => l.slug === slug && t(l.at) >= firstAt - 600_000 && t(l.at) <= firstAt);
    const base = ls.filter((l) => t(l.at) <= firstAt - 300_000).at(-1)?.asks[leg] ?? null;
    // The book time is only kept when the book was being read up to the goal's first sighting.
    const lastPoll = ls.at(-1);
    const bookCovered = lastPoll !== undefined && firstAt - t(lastPoll.at) <= 2 * bookEvery(slug) * 1000;
    if (base !== null && bookCovered && firstAt - prevGoalAt >= 300_000) {
      for (let j = ls.length - 1; j >= 0; j--) {
        const a = ls[j]!.asks[leg];
        if (a === null || units(a) - units(base) < FIVE_CENTS) break;
        bookAt = t(ls[j]!.at);
      }
    }
    rows.push({
      slug, from: c.from, to,
      bookEveryS: bookEvery(slug),
      bookAt: bookAt === null ? null : new Date(bookAt).toISOString(),
      gammaAt: c.gamma?.at ?? null, oursAt: c.ours?.at ?? null, oursObservedAt: c.ours?.scoresObservedAt ?? null,
      gammaFailed: failed("gamma", c.gamma ? t(c.gamma.at) : undefined),
      oursFailed: failed("0xinsider", c.ours ? t(c.ours.at) : undefined),
      oursMinusGammaS: c.gamma && c.ours ? Math.round((t(c.ours.at) - t(c.gamma.at)) / 1000) : null,
      gammaAfterBookS: bookAt !== null && c.gamma ? Math.round((t(c.gamma.at) - bookAt) / 1000) : null,
      oursAfterBookS: bookAt !== null && c.ours ? Math.round((t(c.ours.at) - bookAt) / 1000) : null,
    });
  }
}
const clean = rows.filter((r) => !r.gammaFailed && !r.oursFailed && r.oursMinusGammaS !== null);
const vsBook = rows.filter((r) => r.oursAfterBookS !== null && !r.oursFailed && !r.gammaFailed);
console.log(JSON.stringify({
  goals: rows.length,
  bothSourcesClean: clean.length,
  oursFirst: clean.filter((r) => r.oursMinusGammaS! < 0).length,
  gammaFirst: clean.filter((r) => r.oursMinusGammaS! > 0).length,
  sameTenSeconds: clean.filter((r) => Math.abs(r.oursMinusGammaS!) < 10).length,
  medianOursMinusGammaS: median(clean.map((r) => r.oursMinusGammaS!)),
  withBook: vsBook.length,
  medianGammaAfterBookS: median(vsBook.flatMap((r) => (r.gammaAfterBookS === null ? [] : [r.gammaAfterBookS]))),
  medianOursAfterBookS: median(vsBook.map((r) => r.oursAfterBookS!)),
  rows,
}, null, 1));
