# Emits the LIVE_GOALS and LIVE_SCORES exports from depth-summary and score-race-summary output.
# Run: jq -rn --slurpfile d depth-summary.json --slurpfile r score-race-summary.json --slurpfile l score-lag.json -f gen-live-evidence.jq
($d[0]) as $d | ($r[0]) as $r |
($d.goalProfile | map(select(.medianShare != null))) as $p |
($p | min_by(.medianShare)) as $low |
"
/**
 * Each moneyline book's depth within 2 cents of the midpoint around a goal, as a share of its own
 * median 8 to 4 minutes before (depth-summary output, `goalProfile`). Time zero is the 30-second poll
 * where the 0xinsider games API first showed the new score; " + ($d.profileGoals | tostring) + " goals across the
 * Champions League and EFL Championship games, every Yes book of each game.
 */
export const LIVE_GOALS = {
  goals: " + ($d.profileGoals | tostring) + ",
  lowShare: " + ($low.medianShare | tostring) + ",
  lowOffsetS: " + ($low.offsetS | tostring) + ",
  atScoreShare: " + ($p[] | select(.offsetS == 0) | .medianShare | tostring) + ",
  profile: [
" + ($p | map("    { offsetS: \(.offsetS), books: \(.books), medianShare: \(.medianShare) },") | join("\n")) + "
  ],
} as const;

/**
 * When each source showed a goal (score-race-summary output). Gamma's event `score` and the 0xinsider
 * live games list were read every 10 seconds; the book time is the first poll from which the scoring
 * side's Yes ask stayed 5 cents or more above its level 5 minutes earlier (5-second polls for the
 * Champions League games, 30-second polls for the EFL Championship). Goals where a source's read was
 * failing are left out.
 */
export const LIVE_SCORES = {
  goals: " + ($r.goals | tostring) + ",
  bothClean: " + ($r.bothSourcesClean | tostring) + ",
  oursFirst: " + ($r.oursFirst | tostring) + ",
  gammaFirst: " + ($r.gammaFirst | tostring) + ",
  medianOursMinusGammaS: " + ($r.medianOursMinusGammaS | tostring) + ",
  withBook: " + ($r.withBook | tostring) + ",
  medianOursAfterBookS: " + ($r.medianOursAfterBookS | tostring) + ",
  medianGammaAfterBookS: " + ($r.medianGammaAfterBookS | tostring) + ",
  rows: [
" + ($r.rows | map(select(.oursAfterBookS != null and .gammaAfterBookS != null and (.oursFailed | not) and (.gammaFailed | not))) | map("    { slug: \"\(.slug)\", to: \"\(.to)\", bookAt: \"\(.bookAt)\", bookEveryS: \(.bookEveryS), oursAfterBookS: \(.oursAfterBookS), gammaAfterBookS: \(.gammaAfterBookS) },") | join("\n")) + "
  ],
} as const;"
+ "

/**
 * How long after the book the 0xinsider games API showed each Champions League goal (score-lag
 * output, run on the #32509 study's live-arb-poll log: books every 5 seconds, the score every 30).
 * The book moved at the first poll from which the scoring side's Yes ask stayed 5 cents or more above
 * its level 5 minutes before the score read; goals within 5 minutes of the game's previous goal are
 * left out.
 */
export const LIVE_SCORE_LAG = {
  goals: " + ($l[0].goals | tostring) + ",
  measured: " + ($l[0].measured | tostring) + ",
  medianLagS: " + ($l[0].medianLagS | tostring) + ",
  minLagS: " + ($l[0].minLagS | tostring) + ",
  maxLagS: " + ($l[0].maxLagS | tostring) + ",
} as const;"
