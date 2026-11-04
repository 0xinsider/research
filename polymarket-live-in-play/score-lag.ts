// How far behind the order book does a polled score arrive? Reads live-arb-poll.ts output (Yes asks of
// home, draw and away every 5 s from Polymarket's CLOB; the score from the 0xinsider games API every
// 30 s). For each score change, the scoring side's ask at the first poll showing the new score is
// compared with the asks before it: the book "moved" at the first poll from which the scoring side's
// ask stayed at least 5 cents above its level 5 minutes before the score read, through the score read.
// The lag is the score read time minus that poll. Because the score is read every 30 s, each lag
// includes up to 30 s of polling; the book side is resolved to 5 s. A goal whose game changed score
// less than 5 minutes before is left out, because its look-back would start before the earlier goal.
// Run: node score-lag.ts live.jsonl
import { readFileSync } from "node:fs";

interface Line { at: string; slug: string; state: string; score: string; asks: (number | null)[] }
const lines = readFileSync(process.argv[2] ?? "live.jsonl", "utf8").trim().split("\n").map((l) => JSON.parse(l) as Line);

const median = (xs: number[]) => {
  const s = [...xs].sort((a, b) => a - b);
  return s.length === 0 ? null : s.length % 2 ? s[(s.length - 1) / 2]! : (s[s.length / 2 - 1]! + s[s.length / 2]!) / 2;
};
// Prices compare in whole hundredths of a cent, which every Polymarket tick converts to exactly: in
// floating point 0.97 - 0.92 is 0.04999999999999993, so a 5-cent move tested in dollars falls short.
const units = (price: number) => Math.round(price * 10_000);
const FIVE_CENTS = 500;
const goals: { slug: string; scoreAt: string; from: string; to: string; side: "home" | "away"; movedAt: string | null; lagS: number | null; askBefore: number | null; askAtScore: number | null }[] = [];
for (const slug of new Set(lines.map((l) => l.slug))) {
  const ls = lines.filter((l) => l.slug === slug && l.state === "live" && /^\d+-\d+$/.test(l.score));
  let lastChange = -Infinity;
  for (let i = 1; i < ls.length; i++) {
    const [prev, cur] = [ls[i - 1]!, ls[i]!];
    if (prev.score === cur.score) continue;
    const since = Date.parse(cur.at) - lastChange;
    lastChange = Date.parse(cur.at);
    if (since < 300_000) continue;
    const [h0, a0] = prev.score.split("-").map(Number) as [number, number];
    const [h1, a1] = cur.score.split("-").map(Number) as [number, number];
    // One goal at a time; a score that jumps by more than one goal, or goes down (a correction), is skipped.
    if (h1 + a1 !== h0 + a0 + 1) continue;
    const side = h1 > h0 ? "home" : "away";
    const leg = side === "home" ? 0 : 2;
    const t = Date.parse(cur.at);
    const window = ls.filter((l) => Date.parse(l.at) >= t - 600_000 && Date.parse(l.at) <= t);
    const baseAsk = window.filter((l) => Date.parse(l.at) <= t - 300_000).at(-1)?.asks[leg] ?? null;
    let movedAt: string | null = null;
    if (baseAsk !== null) {
      // The earliest poll from which the ask stays 5 cents or more above the base through the score read.
      for (let j = window.length - 1; j >= 0; j--) {
        const a = window[j]!.asks[leg];
        if (a === null || units(a) - units(baseAsk) < FIVE_CENTS) break;
        movedAt = window[j]!.at;
      }
    }
    goals.push({
      slug, scoreAt: cur.at, from: prev.score, to: cur.score, side, movedAt,
      lagS: movedAt ? Math.round((t - Date.parse(movedAt)) / 1000) : null,
      askBefore: baseAsk, askAtScore: cur.asks[leg] ?? null,
    });
  }
}
const lags = goals.flatMap((g) => (g.lagS === null ? [] : [g.lagS]));
console.log(JSON.stringify({ goals: goals.length, measured: lags.length, medianLagS: median(lags), minLagS: Math.min(...lags), maxLagS: Math.max(...lags), rows: goals }, null, 1));
