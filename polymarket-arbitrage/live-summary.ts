// Summarizes the two in-play logs: live-arb-poll.ts (Polymarket only) and cross-live-poll.ts
// (Polymarket and Kalshi). Only polls taken while the 0xinsider games API called the game live count.
// A "goal window" is the two minutes after the logged score changed; the score is read every 30
// seconds, so a goal can sit up to 30 seconds before its window starts.
// After-fee figures use Polymarket's taker fee, rate x p x (1 - p) a share with the Sports rate 0.05
// (docs trading/fees); Kalshi's fee is left out, so a cross-venue after-fee cost is a floor. The
// optional third log, live-sale-poll.ts, adds the size resting at each best bid.
// Run: node live-summary.ts live.jsonl cross-live.jsonl [sale.jsonl]
import { readFileSync } from "node:fs";

interface PmLine { at: string; slug: string; state: string; clock: string; score: string; asks: (number | null)[]; bids: (number | null)[]; sumAsks: number | null; sumBids: number | null; setCost: { "100": number | null; "1000": number | null } }
interface CrossLine { kalshiAt: string; pmAt: string; slug: string; state: string; score: string; legs: { pmAsk: number | null; pmBid: number | null; kAsk: number | null; kBid: number | null }[]; crossSumAsks: number | null; pmSumAsks: number | null; kalshiSumAsks: number | null }

const read = <T>(path: string) => readFileSync(path, "utf8").trim().split("\n").filter(Boolean).map((l) => JSON.parse(l) as T);
const pm = read<PmLine>(process.argv[2] ?? "live.jsonl");
const cross = read<CrossLine>(process.argv[3] ?? "cross-live.jsonl");
interface SaleLine { at: string; slug: string; bids: number[]; bidSizes: number[]; sumBids: number; netAtBest: number; setsAtBest: number }
const sale = process.argv[4] ? read<SaleLine>(process.argv[4]) : [];
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

// Both venues.
const xLive = cross.filter((l) => l.state === "live" && l.crossSumAsks !== null);
const xGoals = goals(cross, (l) => Date.parse(l.pmAt));
const under = xLive.filter((l) => l.crossSumAsks! < 1);
// Runs: consecutive polls of one game under $1.
const runs: { slug: string; polls: number; min: number }[] = [];
for (const slug of new Set(xLive.map((l) => l.slug))) {
  let run: CrossLine[] = [];
  const flush = () => { if (run.length) runs.push({ slug, polls: run.length, min: Math.min(...run.map((l) => l.crossSumAsks!)) }); run = []; };
  for (const l of xLive.filter((x) => x.slug === slug)) (l.crossSumAsks! < 1 ? run.push(l) : flush());
  flush();
}
// Who moved: for each sub-$1 poll, the leg where the two venues' asks were furthest apart, and the
// first poll of the same game at least 60 seconds later. The venue whose ask moved more toward the
// other one was the stale quote; the gap closing by both or neither is "both" or "open".
const closers = { kalshi: 0, polymarket: 0, both: 0, open: 0, noLater: 0 };
for (const l of under) {
  const t = Date.parse(l.pmAt);
  const later = xLive.find((x) => x.slug === l.slug && Date.parse(x.pmAt) >= t + 60_000);
  if (!later) { closers.noLater++; continue; }
  const gaps = l.legs.map((g) => Math.abs((g.pmAsk ?? 0) - (g.kAsk ?? 0)));
  const i = gaps.indexOf(Math.max(...gaps));
  const [g0, g1] = [l.legs[i]!, later.legs[i]!];
  const pmMove = Math.abs((g1.pmAsk ?? 0) - (g0.pmAsk ?? 0));
  const kMove = Math.abs((g1.kAsk ?? 0) - (g0.kAsk ?? 0));
  const closed = Math.abs((g1.pmAsk ?? 0) - (g1.kAsk ?? 0)) < gaps[i]! / 2;
  if (!closed) closers.open++;
  else if (kMove > 2 * pmMove) closers.kalshi++;
  else if (pmMove > 2 * kMove) closers.polymarket++;
  else closers.both++;
}
const lag = cross.map((l) => Date.parse(l.pmAt) - Date.parse(l.kalshiAt));

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
  cross: {
    first: xLive[0]?.pmAt, last: xLive.at(-1)?.pmAt, games: new Set(xLive.map((l) => l.slug)).size, polls: xLive.length,
    goals: [...xGoals.values()].reduce((x, g) => x + g.length, 0),
    under1: under.length, under1Pct: r4((100 * under.length) / xLive.length), minCross: Math.min(...xLive.map((l) => l.crossSumAsks!)),
    medianCross: median(xLive.map((l) => l.crossSumAsks!)),
    under98: xLive.filter((l) => l.crossSumAsks! < 0.98).length,
    under97: xLive.filter((l) => l.crossSumAsks! < 0.97).length,
    under1InGoalWindow: under.filter((l) => inGoalWindow(xGoals, l.slug, Date.parse(l.pmAt))).length,
    pmAloneUnder1: xLive.filter((l) => l.pmSumAsks !== null && l.pmSumAsks < 1).length,
    kalshiAloneUnder1: xLive.filter((l) => l.kalshiSumAsks !== null && l.kalshiSumAsks < 1).length,
    runs: { count: runs.length, single: runs.filter((r) => r.polls === 1).length, longest: Math.max(0, ...runs.map((r) => r.polls)), median: median(runs.map((r) => r.polls)) },
    staleVenue: closers,
    readLagMs: { median: median(lag), max: Math.max(...lag) },
    // Polymarket legs carry its fee; Kalshi legs carry none. Each leg is the venue with the lower ask.
    under1AfterPolymarketFee: xLive.filter((l) => l.legs.reduce((x, g) => {
      const pmA = g.pmAsk ?? Infinity, kA = g.kAsk ?? Infinity;
      return x + (pmA <= kA ? pmA + fee(pmA) : kA);
    }, 0) < 1).length,
    gamesUnder1: Object.fromEntries([...new Set(under.map((l) => l.slug))].map((s) => [s, under.filter((l) => l.slug === s).length])),
  },
  sale: sale.length === 0 ? null : {
    first: sale[0]!.at, last: sale.at(-1)!.at, polls: sale.length, games: new Set(sale.map((l) => l.slug)).size,
    grossOver1: sale.filter((l) => l.sumBids > 1).length,
    maxNet: Math.max(...sale.map((l) => l.netAtBest)),
    netOver1: sale.filter((l) => l.netAtBest > 1).map((l) => ({ at: l.at, slug: l.slug, bids: l.bids, bidSizes: l.bidSizes, net: l.netAtBest, sets: l.setsAtBest })),
  },
}, null, 1));
