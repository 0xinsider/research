# Emits ARB_IN_PLAY for web/src/lib/research-evidence/polymarket-arbitrage-bot.ts from live-summary output.
# Run: jq -rn --slurpfile s live-summary.json -f gen-in-play.jq
($s[0]) as $x | ($x.polymarket) as $p | ($x.cross) as $c | ($x.sale) as $l |
"/**
 * In play (live-summary output over the live-arb-poll, cross-live-poll and live-sale-poll logs). Polymarket
 * books every 5 seconds on the Champions League games; Polymarket and Kalshi every 10 seconds on
 * Champions League and EFL Championship games; only polls the 0xinsider games API called live count.
 * After-fee figures carry Polymarket's taker fee only.
 */
export const ARB_IN_PLAY = {
  polymarket: {
    first: \"" + $p.first + "\",
    last: \"" + $p.last + "\",
    games: " + ($p.games | length | tostring) + ",
    polls: " + ($p.polls | tostring) + ",
    goals: " + ($p.goals | tostring) + ",
    /** Reads where a leg had no ask at all, so no set could be bought; left out of every asks figure. */
    missingAsk: " + ($p.missingAsk | tostring) + ",
    under1: " + ($p.under1 | tostring) + ",
    minSumAsks: " + ($p.minSumAsks | tostring) + ",
    medianSumAsks: " + ($p.medianSumAsks | tostring) + ",
    minBuyAfterFee: " + ($p.afterFee.minBuy | tostring) + ",
    buyUnder1AfterFee: " + ($p.afterFee.buyUnder1 | tostring) + ",
    /** Of those, reads where 100 of each outcome, walked down the ladders, still cost under $1 with the fee. */
    buyUnder1At100: " + ($p.afterFee.buyUnder1At100 | tostring) + ",
    buyUnder1Rows: [
" + ($p.afterFee.buyUnder1Rows | map("      { at: \"\(.at)\", slug: \"\(.slug)\", score: \"\(.score)\", asks: [\(.asks | map(tostring) | join(", "))], net: \(.net), cost100: \(.cost100), scoreReadS: \(.scoreReadS) },") | join("\n")) + "
    ],
    goalWindowMedianSumAsks: " + ($p.goalWindow.medianSumAsks | tostring) + ",
    goalWindowMaxSumAsks: " + ($p.goalWindow.maxSumAsks | tostring) + ",
    bidsOver1: " + ($p.bidsOver1 | tostring) + ",
    maxSellAfterFee: " + ($p.afterFee.maxSell | tostring) + ",
    /** `scoreReadS`: seconds to the nearest score change the 0xinsider list showed in that game, within 5 minutes (negative: the score read came first), or null. */
    sellOver1AfterFee: [
" + ($p.afterFee.sellOver1 | map("      { at: \"\(.at)\", slug: \"\(.slug)\", score: \"\(.score)\", bids: [\(.bids | map(tostring) | join(", "))], net: \(.net), scoreReadS: \(.scoreReadS) },") | join("\n")) + "
    ],
  },
  cross: {
    first: \"" + $c.first + "\",
    last: \"" + $c.last + "\",
    games: " + ($c.games | tostring) + ",
    polls: " + ($c.polls | tostring) + ",
    goals: " + ($c.goals | tostring) + ",
    under1: " + ($c.under1 | tostring) + ",
    under1Pct: " + ($c.under1Pct | tostring) + ",
    minCross: " + ($c.minCross | tostring) + ",
    medianCross: " + ($c.medianCross | tostring) + ",
    under1AfterPolymarketFee: " + ($c.under1AfterPolymarketFee | tostring) + ",
    under1InGoalWindow: " + ($c.under1InGoalWindow | tostring) + ",
    runs: { count: " + ($c.runs.count | tostring) + ", single: " + ($c.runs.single | tostring) + ", longest: " + ($c.runs.longest | tostring) + " },
    staleVenue: { kalshi: " + ($c.staleVenue.kalshi | tostring) + ", polymarket: " + ($c.staleVenue.polymarket | tostring) + ", both: " + ($c.staleVenue.both | tostring) + ", open: " + ($c.staleVenue.open | tostring) + ", noLater: " + ($c.staleVenue.noLater | tostring) + " },
  },
  sale: {
    first: \"" + $l.first + "\",
    last: \"" + $l.last + "\",
    games: " + ($l.games | tostring) + ",
    polls: " + ($l.polls | tostring) + ",
    grossOver1: " + ($l.grossOver1 | tostring) + ",
    maxNet: " + ($l.maxNet | tostring) + ",
    netOver1: " + ($l.netOver1 | length | tostring) + ",
    /** Reads whose best bids, net of the fee, paid over $1; `sets` is the smallest best-bid size of the three legs. */
    netOver1Rows: [
" + ($l.netOver1 | map("      { at: \"\(.at)\", slug: \"\(.slug)\", bids: [\(.bids | map(tostring) | join(", "))], bidSizes: [\(.bidSizes | map(tostring) | join(", "))], net: \(.net), sets: \(.sets) },") | join("\n")) + "
    ],
  },
} as const;"
