// Turns the scan outputs into the figures the article prints. Reads arb-scan.json (arb-scan.ts)
// and cross-venue.json (cross-venue-scan.ts) from the paths given, writes one JSON object.
// Run: node derive.ts arb-scan.json cross-venue.json
import { readFileSync } from "node:fs";

interface Depth { cost: number; fee: number }
interface Row { event: string; league: string; kickoff: string; state: string; asks: number[]; bids: number[]; sumAsks: number; sumBids: number; feeAtBest: number; depth: Record<string, Depth | null> }
interface Cross { event: string; title: string; state: string; series: string; pmSumAsks: number; kalshiSumAsks: number; crossSumAsks: number; crossAllIn: number; crossSumBids: number; midGapPts: number; legs: { side: string; pmAsk: number; kAsk: number; cheaper: string }[] }

const arb = JSON.parse(readFileSync(process.argv[2] ?? "arb-scan.json", "utf8")) as { readAt: string; rows: Row[] };
const cross = JSON.parse(readFileSync(process.argv[3] ?? "cross-venue.json", "utf8")) as { readAt: string; rows: Cross[] };

const median = (xs: number[]) => {
  const s = [...xs].sort((a, b) => a - b);
  return s.length === 0 ? null : s.length % 2 ? s[(s.length - 1) / 2]! : (s[s.length / 2 - 1]! + s[s.length / 2]!) / 2;
};
const r4 = (x: number | null) => (x === null ? null : Number(x.toFixed(4)));
const rows = arb.rows;

// Sum of asks, cent buckets to $1.10, then two tails.
const cents = (x: number) => Math.round(x * 100);
const buckets = [...Array.from({ length: 11 }, (_, i) => ({ label: (1 + i / 100).toFixed(2), test: (c: number) => c === 100 + i })),
  { label: "1.11-1.15", test: (c: number) => c >= 111 && c <= 115 }, { label: "over 1.15", test: (c: number) => c > 115 }];
const histogram = buckets.map((b) => ({ label: b.label, sets: rows.filter((r) => b.test(cents(r.sumAsks))).length }));

// The busiest leagues by set count, priced books only (sum of asks at most $1.15).
const real = rows.filter((r) => cents(r.sumAsks) <= 115);
const byLeague = Object.entries(Object.groupBy(real, (r) => r.league))
  .map(([league, rs]) => ({ league, sets: rs!.length, medianSumAsks: r4(median(rs!.map((r) => r.sumAsks))), medianSumBids: r4(median(rs!.map((r) => r.sumBids))), minSumAsks: Math.min(...rs!.map((r) => r.sumAsks)), maxSumBids: Math.max(...rs!.map((r) => r.sumBids)) }))
  .sort((a, b) => b.sets - a.sets).slice(0, 8);

// Fee on top of the cheapest sets.
const cheapest = [...rows].sort((a, b) => a.sumAsks - b.sumAsks || a.feeAtBest - b.feeAtBest).slice(0, 6)
  .map((r) => ({ event: r.event, asks: r.asks, sumAsks: r.sumAsks, feeAtBest: r.feeAtBest, allIn: r4(r.sumAsks + r.feeAtBest) }));

// Depth: the sets fillable at every size, so each column holds the same games.
const sizes = ["100", "500", "1000", "5000"];
const deep = rows.filter((r) => sizes.every((s) => r.depth[s] !== null));
const depth = {
  sets: deep.length,
  atBest: r4(median(deep.map((r) => r.sumAsks))),
  bySize: sizes.map((s) => ({ shares: Number(s), medianCost: r4(median(deep.map((r) => r.depth[s]!.cost))), medianFee: r4(median(deep.map((r) => r.depth[s]!.fee))), medianAllIn: r4(median(deep.map((r) => r.depth[s]!.cost + r.depth[s]!.fee))) })),
  fillable: Object.fromEntries(sizes.map((s) => [s, rows.filter((r) => r.depth[s] !== null).length])),
};

// Cross-venue: buckets of the cheaper-venue sum, and the sets under $1.
const crossBuckets = [{ label: "under 1.00", test: (c: number) => c < 100 }, ...Array.from({ length: 5 }, (_, i) => ({ label: (1 + i / 100).toFixed(2), test: (c: number) => c === 100 + i })), { label: "1.05 and up", test: (c: number) => c >= 105 }];
const crossCents = (x: number) => Math.round(x * 1000) / 10;
const crossHistogram = crossBuckets.map((b) => ({ label: b.label, games: cross.rows.filter((r) => b.test(Math.floor(crossCents(r.crossSumAsks) + 1e-6))).length }));
const under1 = cross.rows.filter((r) => r.crossSumAsks < 1).map((r) => ({ event: r.event, title: r.title, state: r.state, crossSumAsks: r.crossSumAsks, crossAllIn: r.crossAllIn, legs: r.legs }));

console.log(JSON.stringify({
  arbReadAt: arb.readAt, crossReadAt: cross.readAt,
  sets: rows.length, histogram, byLeague, cheapest, depth,
  medianFeeAtBest: r4(median(rows.map((r) => r.feeAtBest))),
  medianSpreadOfSet: r4(median(rows.map((r) => r.sumAsks - r.sumBids))),
  realBooks: real.length,
  cross: { games: cross.rows.length, histogram: crossHistogram, under1, medianPm: median(cross.rows.map((r) => r.pmSumAsks)), medianKalshi: median(cross.rows.map((r) => r.kalshiSumAsks)), medianCross: median(cross.rows.map((r) => r.crossSumAsks)), medianAllIn: r4(median(cross.rows.map((r) => r.crossAllIn))), allInUnder1: cross.rows.filter((r) => r.crossAllIn < 1).length, maxBids: Math.max(...cross.rows.map((r) => r.crossSumBids)), medianMidGap: median(cross.rows.map((r) => r.midGapPts)), midGapWithin1: cross.rows.filter((r) => r.midGapPts <= 1 + 1e-9).length },
}, null, 1));
