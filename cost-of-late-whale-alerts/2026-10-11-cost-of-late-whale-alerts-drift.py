"""#23694 (epic #23652, slice R7): what a delay cost on the large buys whose market was still open a day later.

Input: the cohort CSV that query E of 2026-10-11-cost-of-late-whale-alerts-charts.sql.txt returns
(every Polymarket large BUY recorded from 2026-09-10 to 2026-10-09 UTC, price 2c to 98c, whose
market had not settled 24 hours after the fill).

Step 1, fetch (public, no key): one GET per buy to Polymarket's CLOB price history for the outcome bought,
  https://clob.polymarket.com/prices-history?market=<token_id>&startTs=<fill-1800>&endTs=<fill+88200>&fidelity=1
  saved as <cache_dir>/<id>.json. Run on 2026-10-11 from 14:00 UTC.
Step 2, measure: price(T) is the last history point at or before T and no more than 10 minutes before it.
  Marks: the fill (the last point before it), +5 minutes (a reader acting on a live alert), +1 hour,
  +6 hours and +24 hours (the free feed's delay). A buy without a point inside the bound at a mark is
  missing at that mark, counted and reported, never filled in.
  Cost of waiting = price(mark) - price(+5 minutes), in cents per share of the outcome bought:
  positive means the later reader paid more. Before spread and fees.

Usage: python3 -I late_whale_drift.py <cohort.csv> <cache_dir> <marks_out.csv>
"""
import csv, json, os, statistics, sys, time, urllib.error, urllib.request
from bisect import bisect_right
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor

cohort_path, cache_dir, marks_out = sys.argv[1], sys.argv[2], sys.argv[3]
rows = list(csv.DictReader(open(cohort_path)))
os.makedirs(cache_dir, exist_ok=True)


def fetch(row):
    path = os.path.join(cache_dir, f"{row['id']}.json")
    if os.path.exists(path):
        return
    fill = int(row["fill_ts"])
    url = (f"https://clob.polymarket.com/prices-history?market={row['token_id']}"
           f"&startTs={fill - 1800}&endTs={fill + 86400 + 1800}&fidelity=1")
    for attempt in range(5):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "0xinsider-research/1.0"})
            with urllib.request.urlopen(req, timeout=30) as resp:
                body = resp.read()
            json.loads(body)
            open(path, "wb").write(body)
            return
        except (urllib.error.URLError, TimeoutError, ValueError):
            time.sleep(2 * (attempt + 1))
    raise SystemExit(f"fetch failed for {row['id']}")


with ThreadPoolExecutor(max_workers=6) as pool:
    list(pool.map(fetch, rows))

STALE = 600
MARKS = {"fill": 0, "m5": 300, "h1": 3600, "h6": 21600, "h24": 86400}


def price_at(ts, ps, t):
    i = bisect_right(ts, t) - 1
    if i < 0 or t - ts[i] > STALE:
        return None
    return ps[i]


recs = []
for row in rows:
    hist = sorted(json.load(open(os.path.join(cache_dir, f"{row['id']}.json"))).get("history", []), key=lambda p: p["t"])
    ts, ps = [p["t"] for p in hist], [p["p"] for p in hist]
    rec = {k: price_at(ts, ps, int(row["fill_ts"]) + off) for k, off in MARKS.items()}
    rec.update(id=row["id"], grp=row["grp"], category=row["category"], fill_price=float(row["fill_price"]), token=row["token_id"])
    recs.append(rec)

with open(marks_out, "w", newline="") as fh:
    w = csv.writer(fh)
    w.writerow(["id", "grp", "category", "fill_price", "price_before_fill", "price_5m", "price_1h", "price_6h", "price_24h"])
    for r in recs:
        w.writerow([r["id"], r["grp"], r["category"], r["fill_price"]] + ["" if r[k] is None else r[k] for k in MARKS])


def clustered_half(pairs):
    """95% half-width of the mean, clustered by outcome token (one market side)."""
    xs = [x for _, x in pairs]
    mean = statistics.fmean(xs)
    groups = defaultdict(float)
    for token, x in pairs:
        groups[token] += x - mean
    g = len(groups)
    var = g / (g - 1) * sum(e * e for e in groups.values()) / len(xs) ** 2
    return 1.96 * var ** 0.5, g


def report(label, subset):
    print(f"== {label}: {len(subset)} buys")
    for mark in ("h1", "h6", "h24"):
        pairs = [(r["token"], 100 * (r[mark] - r["m5"])) for r in subset if r["m5"] is not None and r[mark] is not None]
        xs = [x for _, x in pairs]
        half, g = clustered_half(pairs)
        print(f"   {mark} minus 5m: priced {len(xs)}, missing {len(subset) - len(xs)}, outcome tokens {g}; "
              f"median {statistics.median(xs):+.2f}c, mean {statistics.fmean(xs):+.2f}c +-{half:.2f}, "
              f"mean absolute {statistics.fmean(abs(x) for x in xs):.2f}c; "
              f"dearer {sum(x > 0 for x in xs)}, cheaper {sum(x < 0 for x in xs)}, unchanged {sum(x == 0 for x in xs)}")
        if mark == "h24":
            bands = [("cheaper by 5c or more", lambda x: x <= -5), ("cheaper by 1c to 5c", lambda x: -5 < x <= -1),
                     ("within 1c", lambda x: -1 < x < 1), ("dearer by 1c to 5c", lambda x: 1 <= x < 5), ("dearer by 5c or more", lambda x: x >= 5)]
            print("   h24 bands: " + "; ".join(f"{name} {sum(1 for x in xs if test(x))}" for name, test in bands))
    paid = [100 * (r["fill_price"] - r["fill"]) for r in subset if r["fill"] is not None]
    print(f"   the large buy's fill minus the price just before it: priced {len(paid)}, median {statistics.median(paid):+.2f}c, mean {statistics.fmean(paid):+.2f}c")


report("every buy in the cohort", recs)
report("sports", [r for r in recs if r["grp"] == "sports"])
report("everything else", [r for r in recs if r["grp"] == "other"])
