// Summarizes depth-live-poll.ts output: spread and dollars within 2 cents of the midpoint on each
// moneyline book, through the match and around goals, and, when given the pregame book read
// (the market-making scan's books, 2026-11-03 19:19:59Z), the same books before kickoff.
// A goal is the first poll showing a new score; the score is read every poll (30 s), so the
// goal happened up to 30 s before that poll plus the 0xinsider API's own lag. A "goal poll" is that
// poll and the next three (about two minutes); "calm" is every other live poll.
// The goal profile lines each book up on the poll where the score changed and reads its depth every
// 30 seconds from 5 minutes before to 5 minutes after, against its median over 8 to 4 minutes before
// (the nearest poll within 15 seconds of each offset; a book is left out of an offset with no poll).
// A goal less than 8 minutes after the same game's previous goal is left out of the profile.
// Lines marked scoreStale (the score read failed and the last one was kept) never mark a goal, nor
// does a change first seen more than 45 seconds after the poll before it.
// Run: node depth-summary.ts depth-live.jsonl [mm-scan-output.json]
import { readFileSync } from "node:fs";

interface Line { at: string; slug: string; side: string; state: string; clock: string; score: string; scoreStale?: boolean; oneSided?: boolean; spreadC?: number; usd2c?: number; usd5c?: number; delay: number | null }
const lines = readFileSync(process.argv[2] ?? "depth-live.jsonl", "utf8").trim().split("\n").map((l) => JSON.parse(l) as Line);
const pregamePath = process.argv[3];

const median = (xs: number[]) => {
  const s = [...xs].sort((a, b) => a - b);
  return s.length === 0 ? null : s.length % 2 ? s[(s.length - 1) / 2]! : (s[s.length / 2 - 1]! + s[s.length / 2]!) / 2;
};
const round = (x: number | null) => (x === null ? null : Math.round(x));
const league = (slug: string) => slug.split("-")[0]!;
const key = (l: Line) => `${l.slug}|${l.side}`;

// Match minute from the API clock: "1H 7" is minute 7, "2H 52" minute 52 (the clock runs on from 45).
const minute = (clock: string) => {
  const m = /^(1H|2H|ET1|ET2)\s+(\d+)/.exec(clock);
  return m ? Number(m[2]) : null;
};
const live = lines.filter((l) => l.state === "live");
const priced = live.filter((l) => !l.oneSided && l.usd2c !== undefined);

// Goal polls per game.
const polls = new Map<string, string[]>();
for (const l of live) if (!(polls.get(l.slug) ?? []).includes(l.at)) polls.set(l.slug, [...(polls.get(l.slug) ?? []), l.at]);
const goalPolls = new Map<string, Set<string>>();
const goals: { slug: string; at: string; clock: string; from: string; to: string }[] = [];
for (const [slug, ats] of polls) {
  const scoreAt = new Map(live.filter((l) => l.slug === slug).map((l) => [l.at, { score: l.score, clock: l.clock, stale: l.scoreStale === true }]));
  const set = new Set<string>();
  ats.forEach((at, i) => {
    const prev = i > 0 ? scoreAt.get(ats[i - 1]!)!.score : null;
    const cur = scoreAt.get(at)!;
    // A change seen across a gap in the polls (a failed or restarted watcher) has no usable time.
    const gapS = i > 0 ? (Date.parse(at) - Date.parse(ats[i - 1]!)) / 1000 : Infinity;
    if (prev !== null && !cur.stale && gapS <= 45 && prev !== cur.score && /^\d+-\d+$/.test(prev) && /^\d+-\d+$/.test(cur.score)) {
      goals.push({ slug, at, clock: cur.clock, from: prev, to: cur.score });
      for (const a of ats.slice(i, i + 4)) set.add(a);
    }
  });
  goalPolls.set(slug, set);
}
const isGoal = (l: Line) => goalPolls.get(l.slug)?.has(l.at) ?? false;

// Each book's depth at a goal poll against its own median over the ten calm polls before the goal.
const ratios: number[] = [];
const spreadAtGoal: number[] = [];
for (const g of goals) {
  const ats = polls.get(g.slug)!;
  const i = ats.indexOf(g.at);
  for (const side of new Set(priced.filter((l) => l.slug === g.slug).map((l) => l.side))) {
    const book = priced.filter((l) => l.slug === g.slug && l.side === side);
    const before = book.filter((l) => ats.slice(Math.max(0, i - 10), i).includes(l.at) && !isGoal(l)).map((l) => l.usd2c!);
    const at = book.find((l) => l.at === g.at);
    const base = median(before);
    if (at && base && base > 0) ratios.push(at.usd2c! / base);
    if (at) spreadAtGoal.push(at.spreadC!);
  }
}

// Depth against time from the score change, per book, as a share of its own pre-goal level.
const offsets = Array.from({ length: 21 }, (_, i) => (i - 10) * 30);
const profile = offsets.map((o) => ({ offsetS: o, shares: [] as number[] }));
let profileGoals = 0;
for (const g of goals) {
  const g0 = Date.parse(g.at);
  // A goal less than 8 minutes after the game's previous one has that goal in its baseline; skip it.
  if (goals.some((o) => o.slug === g.slug && Date.parse(o.at) < g0 && g0 - Date.parse(o.at) < 480_000)) continue;
  let counted = false;
  for (const side of new Set(priced.filter((l) => l.slug === g.slug).map((l) => l.side))) {
    const book = priced.filter((l) => l.slug === g.slug && l.side === side).map((l) => ({ t: Date.parse(l.at) - g0, usd: l.usd2c! }));
    const base = median(book.filter((b) => b.t >= -480_000 && b.t <= -240_000).map((b) => b.usd));
    if (!base || base <= 0) continue;
    if (!counted) { profileGoals++; counted = true; }
    for (const p of profile) {
      const near = book.filter((b) => Math.abs(b.t - p.offsetS * 1000) <= 15_000).sort((a, b) => Math.abs(a.t - p.offsetS * 1000) - Math.abs(b.t - p.offsetS * 1000))[0];
      if (near) p.shares.push(near.usd / base);
    }
  }
}
const goalProfile = profile.map((p) => ({ offsetS: p.offsetS, books: p.shares.length, medianShare: p.shares.length ? Number(median(p.shares)!.toFixed(3)) : null }));

const bins = [[0, 15], [15, 30], [30, 46], [46, 60], [60, 75], [75, 90], [90, 200]] as const;
const byLeagueMinute = [...new Set(priced.map((l) => league(l.slug)))].map((lg) => ({
  league: lg,
  books: new Set(priced.filter((l) => league(l.slug) === lg).map(key)).size,
  bins: bins.map(([a, b]) => {
    const xs = priced.filter((l) => league(l.slug) === lg && !isGoal(l) && (minute(l.clock) ?? -1) >= a && (minute(l.clock) ?? -1) < b);
    return { from: a, to: b, polls: xs.length, medianSpreadC: median(xs.map((x) => x.spreadC!)), medianUsd2c: round(median(xs.map((x) => x.usd2c!))) };
  }),
  halftime: (() => {
    const xs = priced.filter((l) => league(l.slug) === lg && /^HT|half/i.test(l.clock));
    return { polls: xs.length, medianSpreadC: median(xs.map((x) => x.spreadC!)), medianUsd2c: round(median(xs.map((x) => x.usd2c!))) };
  })(),
}));

const calm = priced.filter((l) => !isGoal(l));
const atGoal = priced.filter(isGoal);
let pregame: unknown = null;
if (pregamePath) {
  const mm = JSON.parse(readFileSync(pregamePath, "utf8")) as { books: { readAt: string; rows: { market: string; spreadC: number; usdWithin2c: number; usdWithin5c: number }[] } };
  // The scan names a book by its market slug: the event slug plus the outcome's short code.
  const legs = mm.books.rows.flatMap((r) => {
    const slug = [...polls.keys()].find((s) => r.market.startsWith(`${s}-`));
    return slug ? [{ ...r, slug }] : [];
  });
  // Which side a scan market is comes from its suffix: "draw", or the team code in the event slug.
  const sideOf = (r: { market: string; slug: string }) => {
    const code = r.market.slice(r.slug.length + 1);
    if (code === "draw") return "draw";
    const teams = r.slug.split("-").slice(1, 3);
    return code === teams[0] ? "home" : code === teams[1] ? "away" : null;
  };
  const matched = legs.flatMap((r) => {
    const side = sideOf(r);
    const inPlay = calm.filter((l) => l.slug === r.slug && l.side === side);
    if (!side || inPlay.length === 0) return [];
    // The first 15 minutes, before most goals move a price toward 0 or 1, where depth near the
    // midpoint means something different.
    const early = inPlay.filter((l) => (minute(l.clock) ?? 99) < 15);
    return [{ market: r.market, pregameSpreadC: r.spreadC, pregameUsd2c: r.usdWithin2c, inPlaySpreadC: median(inPlay.map((l) => l.spreadC!)), inPlayUsd2c: round(median(inPlay.map((l) => l.usd2c!))), inPlayPolls: inPlay.length, earlyUsd2c: round(median(early.map((l) => l.usd2c!))), earlyPolls: early.length }];
  });
  pregame = {
    readAt: mm.books.readAt,
    books: matched.length,
    medianPregameUsd2c: round(median(matched.map((m) => m.pregameUsd2c))),
    medianInPlayUsd2c: round(median(matched.map((m) => m.inPlayUsd2c!))),
    medianRatio: Number(median(matched.map((m) => m.inPlayUsd2c! / m.pregameUsd2c))!.toFixed(3)),
    medianEarlyUsd2c: round(median(matched.flatMap((m) => (m.earlyUsd2c === null ? [] : [m.earlyUsd2c])))),
    medianEarlyRatio: Number(median(matched.flatMap((m) => (m.earlyUsd2c === null ? [] : [m.earlyUsd2c / m.pregameUsd2c])))!.toFixed(3)),
    rows: matched,
  };
}

console.log(JSON.stringify({
  first: live[0]?.at,
  last: live.at(-1)?.at,
  games: polls.size,
  books: new Set(priced.map(key)).size,
  bookPolls: priced.length,
  oneSidedPolls: live.filter((l) => l.oneSided).length,
  delays: Object.fromEntries([...new Set(lines.map((l) => String(l.delay)))].map((d) => [d, lines.filter((l) => String(l.delay) === d).length])),
  delayByState: Object.fromEntries([...new Set(lines.map((l) => `${l.state}|${String(l.delay)}`))].map((k) => [k, lines.filter((l) => `${l.state}|${String(l.delay)}` === k).length])),
  goals,
  calm: { polls: calm.length, medianSpreadC: median(calm.map((l) => l.spreadC!)), medianUsd2c: round(median(calm.map((l) => l.usd2c!))) },
  goalPolls: { polls: atGoal.length, medianSpreadC: median(atGoal.map((l) => l.spreadC!)), medianUsd2c: round(median(atGoal.map((l) => l.usd2c!))) },
  goalVsBefore: { books: ratios.length, medianRatio: ratios.length ? Number(median(ratios)!.toFixed(3)) : null, under25pct: ratios.filter((r) => r < 0.25).length, under50pct: ratios.filter((r) => r < 0.5).length, medianSpreadAtGoalC: median(spreadAtGoal) },
  profileGoals,
  goalProfile,
  byLeagueMinute,
  pregame,
}, null, 1));
