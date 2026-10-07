#!/usr/bin/env python3
"""Grade-vs-price, corrected run of 2026-10-07: pool the exports into the published tables.

Reads the per-(grade, wallet, market) exports that queries.sql writes (queries 4 and 5),
prints every table in results.md, and writes cluster_stats.csv, the sums every 95% interval
is built from. The exports carry internal wallet ids and are not committed; cluster_stats.csv
is, and intervals.py recomputes every interval from it with no database access.

    python3 aggregate.py export_2026-06-01_2026-07-25.csv export_2026-07-25_2026-09-20.csv \
        export_2026-09-20_2026-10-07.csv month_start.csv

Edge = share of buys that won minus average price paid. A 95% interval is 1.96 standard
errors of that ratio, clustered by market and, separately, by wallet; the wider is reported.
"""

import collections
import csv
import math
import sys

GROUPS = {
    "S": {"S"}, "A": {"A"}, "B": {"B"}, "C": {"C"}, "D": {"D"}, "F": {"F"}, "none": {"none"},
    "S/A": {"S", "A"}, "S/A/B": {"S", "A", "B"}, "D/F": {"D", "F"}, "all": None,
}
PRICE_BANDS = {1: "under 20c", 2: "20-40c", 3: "40-60c", 4: "60-80c", 5: "80c and up"}


def load(path, window):
    rows = []
    with open(path) as fh:
        for r in csv.DictReader(fh):
            rows.append({
                "window": window, "src": r.get("src", "pit"), "g": r["g"],
                "pb": int(r["pb"]) if r.get("pb") else 0, "cat": r.get("cat", ""),
                "origin": r.get("origin", ""), "wallet": r["trader_id"], "market": r["mkt"],
                "n": int(float(r["n"])), "s": float(r["s"]), "wins": int(float(r["wins"])),
                "sp": float(r["sp"]), "usd": float(r["usd"]),
            })
    return rows


def sums(sel, key):
    """Per-cluster n and sum(won - price), then k, N, S, sum s^2, sum s*n, sum n^2."""
    cl = collections.defaultdict(lambda: [0, 0.0])
    for r in sel:
        cl[r[key]][0] += r["n"]
        cl[r[key]][1] += r["s"]
    k = len(cl)
    return {
        "k": k, "n": sum(n for n, _ in cl.values()), "s": sum(s for _, s in cl.values()),
        "ss": sum(s * s for _, s in cl.values()), "sn": sum(s * n for n, s in cl.values()),
        "nn": sum(n * n for n, _ in cl.values()),
    }


def half_width(m):
    e = m["s"] / m["n"]
    v = m["k"] / max(m["k"] - 1, 1) * (m["ss"] - 2 * e * m["sn"] + e * e * m["nn"]) / m["n"] ** 2
    return 1.96 * math.sqrt(max(v, 0.0))


def main(paths):
    *exports, month_path = paths
    windows = ["a1", "a2", "b"]
    rows = [r for path, w in zip(exports, windows) for r in load(path, w)]
    month = load(month_path, "month")
    designs = {
        "headline": (rows, lambda r: True),
        "ranking_rows_only": (rows, lambda r: r["window"] in ("a1", "a2")),
        "exact_at_fill": (rows, lambda r: r["window"] == "b" and r["src"] == "exact"),
        "month_start": (month, lambda r: r["origin"] in ("2026-07-01", "2026-08-01", "2026-09-01")),
    }
    stats_out = []
    for design, (pool, keep) in designs.items():
        print(f"== {design}")
        print("bucket|trades|wallets|markets|notional_musd|won_pct|price_pct|edge|ci|lo|hi")
        for name, grades in GROUPS.items():
            sel = [r for r in pool if keep(r) and (grades is None or r["g"] in grades)]
            if not sel:
                continue
            m, w = sums(sel, "market"), sums(sel, "wallet")
            e, ci = m["s"] / m["n"], max(half_width(m), half_width(w))
            won = sum(r["wins"] for r in sel) / m["n"]
            price = sum(r["sp"] for r in sel) / m["n"]
            usd = sum(r["usd"] for r in sel)
            print(f"{name}|{m['n']}|{w['k']}|{m['k']}|{usd / 1e6:.1f}|{100 * won:.2f}|{100 * price:.2f}"
                  f"|{100 * e:+.2f}|{100 * ci:.2f}|{100 * (e - ci):+.2f}|{100 * (e + ci):+.2f}")
            for cluster, mm in (("market", m), ("wallet", w)):
                stats_out.append({"design": design, "bucket": name, "cluster": cluster, **mm})
        print()
    print("== headline by price band (S/A, B, D/F)")
    for band, label in PRICE_BANDS.items():
        cells = []
        for name in ("S/A", "B", "D/F"):
            sel = [r for r in rows if r["pb"] == band and r["g"] in GROUPS[name]]
            m, w = sums(sel, "market"), sums(sel, "wallet")
            e, ci = m["s"] / m["n"], max(half_width(m), half_width(w))
            cells.append(f"{name} {100 * e:+.2f} +-{100 * ci:.2f} (n={m['n']})")
            for cluster, mm in (("market", m), ("wallet", w)):
                stats_out.append({"design": f"headline_price_{band}", "bucket": name, "cluster": cluster, **mm})
        print(f"{label} | " + " | ".join(cells))
    print()
    print("== headline, S and A by category, 500 or more buys")
    counts = collections.Counter()
    for r in rows:
        if r["g"] in ("S", "A"):
            counts[r["cat"]] += r["n"]
    total = sum(counts.values())
    for cat, count in counts.most_common():
        if count < 500:
            continue
        sel = [r for r in rows if r["cat"] == cat and r["g"] in ("S", "A")]
        m, w = sums(sel, "market"), sums(sel, "wallet")
        e, ci = m["s"] / m["n"], max(half_width(m), half_width(w))
        print(f"{cat}|{m['n']}|{100 * e:+.2f}|{100 * ci:.2f}|share {100 * m['n'] / total:.1f}%")
        for cluster, mm in (("market", m), ("wallet", w)):
            stats_out.append({"design": "headline_category", "bucket": f"S/A {cat}", "cluster": cluster, **mm})
    with open("cluster_stats.csv", "w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=["design", "bucket", "cluster", "k", "n", "s", "ss", "sn", "nn"])
        writer.writeheader()
        for row in stats_out:
            writer.writerow({key: (f"{value:.10g}" if isinstance(value, float) else value) for key, value in row.items()})


if __name__ == "__main__":
    main(sys.argv[1:])
