// Summarizes kickoff-clear-poll.ts output: for each book, the reads around its gameStartTime in seconds
// from the start, and the resting dollars (bid plus ask, price times size) as a share of the last read
// before the start, so a book cleared at the start shows its resting dollars falling and rebuilding.
// Run: node kickoff-summary.ts kickoff.jsonl
import { readFileSync } from "node:fs";

interface Line { at: string; event: string; outcome: string; start: string; bid: number | null; ask: number | null; bidLevels: number; askLevels: number; bidUsd: number; askUsd: number; usd2c: number | null }
const lines = readFileSync(process.argv[2] ?? "kickoff.jsonl", "utf8").trim().split("\n").map((l) => JSON.parse(l) as Line);
const parseStart = (s: string) => Date.parse(s.replace(" ", "T").replace(/\+00$/, "+00:00"));
const median = (xs: number[]) => {
  const s = [...xs].sort((a, b) => a - b);
  return s.length === 0 ? null : s.length % 2 ? s[(s.length - 1) / 2]! : (s[s.length / 2 - 1]! + s[s.length / 2]!) / 2;
};
const round = (x: number | null, d = 3) => (x === null ? null : Number(x.toFixed(d)));

const books = [...new Set(lines.map((l) => `${l.event}|${l.outcome}`))];
const marks = [-60, -10, -2, 0, 2, 5, 10, 20, 30, 60, 120, 300, 600];
const rows = books.map((k) => {
  const ls = lines.filter((l) => `${l.event}|${l.outcome}` === k);
  const start = parseStart(ls[0]!.start);
  const rel = ls.map((l) => ({ ...l, s: (Date.parse(l.at) - start) / 1000, resting: l.bidUsd + l.askUsd }));
  const before = rel.filter((r) => r.s < 0).at(-1);
  const share = (r: { resting: number } | undefined) => (r && before && before.resting > 0 ? r.resting / before.resting : null);
  // The read nearest each mark, within 3 seconds.
  const at = (m: number) => {
    const near = rel.filter((r) => Math.abs(r.s - m) <= 3).sort((a, b) => Math.abs(a.s - m) - Math.abs(b.s - m))[0];
    return near ? { s: round(near.s, 1), levels: near.bidLevels + near.askLevels, resting: Math.round(near.resting), shareOfBefore: round(share(near)), usd2c: near.usd2c === null ? null : Math.round(near.usd2c), bid: near.bid, ask: near.ask } : null;
  };
  // The first read at or after the start whose resting dollars are under half the last pre-start read.
  const firstDrop = rel.find((r) => r.s >= 0 && (share(r) ?? 1) < 0.5);
  return {
    book: k, start: ls[0]!.start, reads: ls.length, first: round(rel[0]?.s ?? null, 1), last: round(rel.at(-1)?.s ?? null, 1),
    before: before ? { s: round(before.s, 1), levels: before.bidLevels + before.askLevels, resting: Math.round(before.resting), usd2c: before.usd2c === null ? null : Math.round(before.usd2c) } : null,
    droppedAt: firstDrop ? round(firstDrop.s, 1) : null, droppedShare: firstDrop ? round(share(firstDrop)) : null,
    marks: Object.fromEntries(marks.map((m) => [m, at(m)])),
  };
});
const watched = rows.filter((r) => r.before && r.last !== null && r.last >= 10);
console.log(JSON.stringify({
  books: rows.length, watchedAcrossStart: watched.length,
  droppedUnderHalf: watched.filter((r) => r.droppedAt !== null).length,
  medianShareAt2s: round(median(watched.flatMap((r) => (r.marks[2]?.shareOfBefore == null ? [] : [r.marks[2].shareOfBefore])))),
  medianShareAt60s: round(median(watched.flatMap((r) => (r.marks[60]?.shareOfBefore == null ? [] : [r.marks[60].shareOfBefore])))),
  medianShareAt600s: round(median(watched.flatMap((r) => (r.marks[600]?.shareOfBefore == null ? [] : [r.marks[600].shareOfBefore])))),
  rows,
}, null, 1));
