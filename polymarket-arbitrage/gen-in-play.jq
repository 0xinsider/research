# Emits ARB_IN_PLAY for web/src/lib/research-evidence/polymarket-arbitrage-bot.ts from live-summary output.
# Run: jq -rn --slurpfile s live-summary.json -f gen-in-play.jq
($s[0]) as $x | ($x.polymarket) as $p | ($x.sale) as $l |
"/**
 * In play (live-summary output over the live-arb-poll and live-sale-poll logs): Polymarket books every
 * 5 seconds on the Champions League games, and best bids with their sizes on Champions League and EFL
 * Championship games from 20:33 UTC. Only polls the 0xinsider games API called live count, and a set only
 * when all three legs had a price. After-fee figures carry Polymarket's taker fee.
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
    /** Reads where a leg had no bid at all, so no set could be sold; left out of every bids figure. */
    missingBid: " + ($p.missingBid | tostring) + ",
    bidsOver1: " + ($p.bidsOver1 | tostring) + ",
    maxSellAfterFee: " + ($p.afterFee.maxSell | tostring) + ",
    /** `scoreReadS`: seconds to the nearest score change the 0xinsider list showed in that game, within 5 minutes (negative: the score read came first), or null. */
    sellOver1AfterFee: [
" + ($p.afterFee.sellOver1 | map("      { at: \"\(.at)\", slug: \"\(.slug)\", score: \"\(.score)\", bids: [\(.bids | map(tostring) | join(", "))], net: \(.net), scoreReadS: \(.scoreReadS) },") | join("\n")) + "
    ],
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
