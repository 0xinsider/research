// Turns the scan output into the figures the article prints. Reads arb-scan.json (arb-scan.ts) from
// the path given and writes one JSON object.
// Run: node derive.ts arb-scan.json
import { readFileSync } from "node:fs";

interface Depth { cost: number; fee: number }
interface Row { event: string; league: string; kickoff: string; state: string; asks: number[]; bids: number[]; sumAsks: number; sumBids: number; feeAtBest: number; depth: Record<string, Depth | null> }

const arb = JSON.parse(readFileSync(process.argv[2] ?? "arb-scan.json", "utf8")) as { readAt: string; rows: Row[] };

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


console.log(JSON.stringify({
  arbReadAt: arb.readAt,
  sets: rows.length, histogram, byLeague, cheapest, depth,
  medianFeeAtBest: r4(median(rows.map((r) => r.feeAtBest))),
  medianSpreadOfSet: r4(median(rows.map((r) => r.sumAsks - r.sumBids))),
  realBooks: real.length,
}, null, 1));
