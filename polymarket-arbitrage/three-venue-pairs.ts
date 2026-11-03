// Cross-venue pair cost from the published three-venue capture (0xinsider/research three-venue-prices/games.csv,
// captured 2026-09-18 16:01Z): the cheapest way to hold both sides of a game across Polymarket and Kalshi at the ask.
import { readFileSync } from "node:fs";
const [header, ...lines] = readFileSync(process.argv[2] ?? "games.csv", "utf8").replace(/\r/g, "").trim().split("\n");
const cols = header!.split(",");
const rows = lines.map((l) => {
  // game names hold no commas in this file except quoted ones; split on commas outside quotes
  const cells = l.match(/("[^"]*"|[^,]*)(,|$)/g)!.map((c) => c.replace(/,$/, "").replace(/^"|"$/g, ""));
  return Object.fromEntries(cols.map((c, i) => [c, cells[i]!]));
});
const num = (r: Record<string, string>, k: string) => Number(r[k]);
const out = rows.map((r) => {
  const pmFavKalDog = num(r, "fav_pm_ask_c") + num(r, "dog_kalshi_ask_c");
  const kalFavPmDog = num(r, "fav_kalshi_ask_c") + num(r, "dog_pm_ask_c");
  const pmFavKalDogFee = num(r, "fav_pm_all_in_c") + num(r, "dog_kalshi_ask_c");
  const kalFavPmDogFee = num(r, "fav_kalshi_ask_c") + num(r, "dog_pm_all_in_c");
  return { game: r.game_short, gap: Math.abs(num(r, "gap_pm_kalshi")), bestPair: Math.min(pmFavKalDog, kalFavPmDog), bestPairWithPmFee: Math.min(pmFavKalDogFee, kalFavPmDogFee), pmBoth: num(r, "fav_pm_ask_c") + num(r, "dog_pm_ask_c"), kalBoth: num(r, "fav_kalshi_ask_c") + num(r, "dog_kalshi_ask_c") };
});
const sorted = (xs: number[]) => [...xs].sort((a, b) => a - b);
const med = (xs: number[]) => { const s = sorted(xs); return s.length % 2 ? s[(s.length - 1) / 2] : (s[s.length / 2 - 1]! + s[s.length / 2]!) / 2; };
const bins = new Map<string, number>();
for (const o of out) bins.set(o.gap.toFixed(1), (bins.get(o.gap.toFixed(1)) ?? 0) + 1);
console.log(JSON.stringify({
  games: out.length,
  gapBins: Object.fromEntries([...bins].sort((a, b) => Number(a[0]) - Number(b[0]))),
  bestPair: { min: Math.min(...out.map((o) => o.bestPair)), median: med(out.map((o) => o.bestPair)), below100: out.filter((o) => o.bestPair < 100).length, at100: out.filter((o) => o.bestPair === 100).length },
  bestPairWithPmFee: { min: Math.min(...out.map((o) => o.bestPairWithPmFee)), median: med(out.map((o) => o.bestPairWithPmFee)), below100: out.filter((o) => o.bestPairWithPmFee < 100).length },
  pmBoth: { min: Math.min(...out.map((o) => o.pmBoth)), median: med(out.map((o) => o.pmBoth)) },
  kalBoth: { min: Math.min(...out.map((o) => o.kalBoth)), median: med(out.map((o) => o.kalBoth)) },
  cheapest: [...out].sort((a, b) => a.bestPair - b.bestPair).slice(0, 5),
}, null, 1));
