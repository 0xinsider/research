"""#23664: the S, A and B cohort's concentration, from query E's per-wallet chunks.

Query E (sharp-money-charts-2026-10-11.sql) ran in four date chunks on the read
replica, each under the 60s statement timeout, and returned one row per wallet graded S, A or B at the
trade: a 12-character md5 prefix of the wallet id, its buys and its dollars. This script adds the chunks
up per wallet and prints the shares the article states. Run: python3 -I <this file> <the .csv beside it>
"""

import collections
import csv
import sys

buys: collections.Counter[str] = collections.Counter()
dollars: collections.Counter[str] = collections.Counter()
with open(sys.argv[1], newline="") as handle:
    for row in csv.DictReader(handle):
        buys[row["wallet"]] += int(row["n"])
        dollars[row["wallet"]] += float(row["usd"])

total_buys = sum(buys.values())
total_dollars = sum(dollars.values())
by_buys = [wallet for wallet, _ in buys.most_common(10)]
top_buys = [buys[wallet] for wallet in by_buys]
top_dollars = [usd for _, usd in dollars.most_common(10)]
print(f"wallets {len(buys)}  buys {total_buys}  dollars_musd {total_dollars / 1e6:.1f}")
print(f"most_buys_wallet {by_buys[0]}  buys {top_buys[0]}  dollars_musd {dollars[by_buys[0]] / 1e6:.1f}")
print(f"most_buys_wallet_buy_share_pct {100 * top_buys[0] / total_buys:.1f}")
print(f"most_buys_wallet_dollar_share_pct {100 * dollars[by_buys[0]] / total_dollars:.1f}")
print(f"most_dollars_wallet {dollars.most_common(1)[0][0]}")
print(f"top10_by_buys_buy_share_pct {100 * sum(top_buys) / total_buys:.1f}")
print(f"top10_by_buys_dollar_share_pct {100 * sum(dollars[w] for w in by_buys) / total_dollars:.1f}")
print(f"top10_by_dollars_dollar_share_pct {100 * sum(top_dollars) / total_dollars:.1f}")
print(f"top10_buys {top_buys}")
