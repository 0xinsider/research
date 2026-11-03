// Summarizes the in-play logs of live-arb-poll.ts (best asks and bids every 5 seconds) and, optionally,
// live-sale-poll.ts (best bids with the size resting at each). Only polls taken while the 0xinsider games
// API called the game live count, and a set's cost or sale value only when all three legs had an ask (or a
// bid). A "goal window" is the two minutes after the logged score changed; the score is read every 30
// seconds, so a goal can sit up to 30 seconds before its window starts.
// After-fee figures use Polymarket's taker fee, rate x p x (1 - p) a share with the Sports rate 0.05
// (docs trading/fees).
// Run: node live-summary.ts live.jsonl [sale.jsonl]
import { readFileSync } from "node:fs";

interface PmLine { at: string; slug: string; state: string; clock: string; score: string; asks: (number | null)[]; bids: (number | null)[]; sumAsks: number | null; sumBids: number | null; setCost: { "100": number | null; "1000": number | null } }

const read = <T>(path: string) => readFileSync(path, "utf8").trim().split("\n").filter(Boolean).map((l) => JSON.parse(l) as T);
const pm = read<PmLine>(process.argv[2] ?? "live.jsonl");
interface SaleLine { at: string; slug: string; bids: number[]; bidSizes: number[]; sumBids: number; netAtBest: number; setsAtBest: number }
const sale = process.argv[3] ? read<SaleLine>(process.argv[3]) : [];
const FEE_RATE = 0.05;
const fee = (p: number) => FEE_RATE * p * (1 - p);
// Cost of one share of each outcome at the best asks, fee in; proceeds of selling one at the best bids, fee out.
const buyNet = (l: PmLine) => l.asks.reduce<number>((x, a) => x + (a ?? NaN) + fee(a ?? 0), 0);
const sellNet = (l: PmLine) => l.bids.reduce<number>((x, b) => x + (b ?? NaN) - fee(b ?? 0), 0);

// Score changes per game, by the first poll that shows the new score.
function goals<T extends { slug: string; score: string; state: string }>(lines: T[], time: (l: T) => number) {
  const out = new Map<string, number[]>();
  const last = new Map<string, string>();
  for (const l of lines) {
    if (l.state !== "live" || !/^\d+-\d+$/.test(l.score)) continue;
    const prev = last.get(l.slug);
    if (prev !== undefined && prev !== l.score) out.set(l.slug, [...(out.get(l.slug) ?? []), time(l)]);
    last.set(l.slug, l.score);
  }
  return out;
}
const inGoalWindow = (marks: Map<string, number[]>, slug: string, t: number) => (marks.get(slug) ?? []).some((g) => t >= g && t < g + 120_000);
const median = (xs: number[]) => {
  const s = [...xs].sort((a, b) => a - b);
  return s.length === 0 ? null : s.length % 2 ? s[(s.length - 1) / 2]! : (s[s.length / 2 - 1]! + s[s.length / 2]!) / 2;
};
const r4 = (x: number | null) => (x === null ? null : Number(x.toFixed(4)));

// Polymarket alone. A leg with no ask (late in a decided game the winner often has none) means no set
// can be bought at that read, so the asks figures use only reads with an ask on all three legs; the
// bids figures likewise. `null < 1` is true in JavaScript, so counting those reads would call them cheap.
const pmLive = pm.filter((l) => l.state === "live");
const hasAll = (xs: (number | null)[]) => xs.length === 3 && xs.every((x) => x !== null);
const pmAsk = pmLive.filter((l) => hasAll(l.asks)) as (PmLine & { sumAsks: number })[];
const pmBid = pmLive.filter((l) => hasAll(l.bids)) as (PmLine & { sumBids: number })[];
const pmGoals = goals(pm, (l) => Date.parse(l.at));
// Seconds from a read to the nearest score change the 0xinsider list showed in the same game, within 5
// minutes either side (positive: the score read came after), or null.
const scoreReadS = (slug: string, at: string) => {
  const t = Date.parse(at);
  const near = (pmGoals.get(slug) ?? []).map((u) => Math.round((u - t) / 1000)).filter((d) => Math.abs(d) <= 300);
  return near.length ? near.reduce((a, b) => (Math.abs(b) < Math.abs(a) ? b : a)) : null;
};
const asks = (ls: PmLine[]) => ls.flatMap((l) => (hasAll(l.asks) ? [l.sumAsks!] : []));
const bids = (ls: PmLine[]) => ls.flatMap((l) => (hasAll(l.bids) ? [l.sumBids!] : []));
const pmGoal = pmLive.filter((l) => inGoalWindow(pmGoals, l.slug, Date.parse(l.at)));
const pmCalm = pmLive.filter((l) => !inGoalWindow(pmGoals, l.slug, Date.parse(l.at)));
const pmGames = [...new Set(pmLive.map((l) => l.slug))].map((slug) => {
  const ls = pmLive.filter((l) => l.slug === slug);
  return {
    slug,
    polls: ls.length,
    goals: (pmGoals.get(slug) ?? []).length,
    finalScore: ls.at(-1)!.score,
    missingAsk: ls.filter((l) => !hasAll(l.asks)).length,
    minSumAsks: Math.min(...ls.flatMap((l) => (hasAll(l.asks) ? [l.sumAsks!] : []))),
    medianSumAsks: median(ls.flatMap((l) => (hasAll(l.asks) ? [l.sumAsks!] : []))),
    maxSumAsks: Math.max(...ls.flatMap((l) => (hasAll(l.asks) ? [l.sumAsks!] : []))),
    maxSumBids: Math.max(...ls.flatMap((l) => (hasAll(l.bids) ? [l.sumBids!] : []))),
    min1000: Math.min(...ls.map((l) => l.setCost["1000"] ?? Infinity)),
  };
});

console.log(JSON.stringify({
  polymarket: {
    first: pmLive[0]?.at, last: pmLive.at(-1)?.at, games: pmGames.length, polls: pmLive.length,
    goals: [...pmGoals.values()].reduce((x, g) => x + g.length, 0),
    missingAsk: pmLive.length - pmAsk.length, missingBid: pmLive.length - pmBid.length,
    under1: pmAsk.filter((l) => l.sumAsks < 1).length, at1: pmAsk.filter((l) => l.sumAsks === 1).length,
    bidsOver1: pmBid.filter((l) => l.sumBids > 1).length,
    afterFee: {
      minBuy: r4(Math.min(...pmLive.map(buyNet).filter(Number.isFinite))),
      buyUnder1: pmLive.filter((l) => buyNet(l) < 1).length,
      // `cost100` is the per-share cost of 100 of each outcome walking the ask ladders, before the fee.
      buyUnder1Rows: pmLive.filter((l) => buyNet(l) < 1).map((l) => ({ at: l.at, slug: l.slug, score: l.score, asks: l.asks, net: r4(buyNet(l)), cost100: l.setCost["100"], scoreReadS: scoreReadS(l.slug, l.at) })),
      buyUnder1At100: pmLive.filter((l) => hasAll(l.asks) && l.setCost["100"] !== null && l.setCost["100"] + l.asks.reduce<number>((x, a) => x + fee(a!), 0) < 1).length,
      maxSell: r4(Math.max(...pmLive.map(sellNet).filter(Number.isFinite))),
      sellOver1: pmLive.filter((l) => sellNet(l) > 1).map((l) => ({ at: l.at, slug: l.slug, score: l.score, bids: l.bids, net: r4(sellNet(l)), scoreReadS: scoreReadS(l.slug, l.at) })),
    },
    minSumAsks: Math.min(...pmAsk.map((l) => l.sumAsks)), medianSumAsks: median(pmAsk.map((l) => l.sumAsks)),
    goalWindow: { polls: pmGoal.length, medianSumAsks: median(asks(pmGoal)), maxSumAsks: asks(pmGoal).length ? Math.max(...asks(pmGoal)) : null, medianSumBids: median(bids(pmGoal)) },
    calm: { polls: pmCalm.length, medianSumAsks: median(asks(pmCalm)), medianSumBids: median(bids(pmCalm)) },
    games: pmGames,
  },
  sale: sale.length === 0 ? null : {
    first: sale[0]!.at, last: sale.at(-1)!.at, polls: sale.length, games: new Set(sale.map((l) => l.slug)).size,
    grossOver1: sale.filter((l) => l.sumBids > 1).length,
    maxNet: Math.max(...sale.map((l) => l.netAtBest)),
    netOver1: sale.filter((l) => l.netAtBest > 1).map((l) => ({ at: l.at, slug: l.slug, bids: l.bids, bidSizes: l.bidSizes, net: l.netAtBest, sets: l.setsAtBest })),
  },
}, null, 1));
