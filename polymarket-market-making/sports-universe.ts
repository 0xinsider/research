// Snapshot of open Polymarket sports markets from the public Gamma API (no key).
// Pages /events by 24h volume until Gamma refuses the offset (422 past offset 2,000),
// then writes one row per market with the fields a market maker reads.
// Run: node sports-universe.ts > universe.json
const GAMMA = "https://gamma-api.polymarket.com";

type GammaMarket = Record<string, unknown> & { clobTokenIds?: string };
type GammaEvent = Record<string, unknown> & { markets?: GammaMarket[]; tags?: { slug: string }[] };

const events: GammaEvent[] = [];
let stop = "";
for (let offset = 0; ; offset += 100) {
  const url = `${GAMMA}/events?tag_slug=sports&closed=false&order=volume24hr&ascending=false&limit=100&offset=${offset}`;
  const res = await fetch(url);
  if (!res.ok) {
    stop = `HTTP ${res.status} at offset ${offset}`;
    break;
  }
  const page = (await res.json()) as GammaEvent[];
  if (page.length === 0) {
    stop = `empty page at offset ${offset}`;
    break;
  }
  events.push(...page);
}

const num = (v: unknown) => (v === null || v === undefined || v === "" ? null : Number(v));
const markets = events.flatMap((e) =>
  (e.markets ?? []).map((m) => ({
    event: e.slug,
    series: e.seriesSlug ?? null,
    esports: (e.tags ?? []).some((t) => t.slug === "esports"),
    slug: m.slug,
    conditionId: m.conditionId,
    tokens: JSON.parse(m.clobTokenIds ?? "[]") as string[],
    type: m.sportsMarketType ?? null,
    acceptingOrders: m.acceptingOrders === true && m.enableOrderBook === true,
    bestBid: num(m.bestBid),
    bestAsk: num(m.bestAsk),
    spread: num(m.spread),
    volume24hr: num(m.volume24hr) ?? 0,
    liquidity: num(m.liquidity) ?? 0,
    feeSchedule: m.feeSchedule ?? null,
    feeType: m.feeType ?? null,
    rewardsMaxSpread: num(m.rewardsMaxSpread),
    rewardsMinSize: num(m.rewardsMinSize),
    tick: num(m.orderPriceMinTickSize),
    minSize: num(m.orderMinSize),
    secondsDelay: num(m.secondsDelay),
    gameStartTime: m.gameStartTime ?? null,
    negRisk: m.negRisk === true,
    outcomes: JSON.parse((m.outcomes as string | undefined) ?? "[]") as string[],
    question: m.question,
  })),
);

console.log(JSON.stringify({ readAt: new Date().toISOString(), events: events.length, stop, markets }));
