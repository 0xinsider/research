"""Check which moneyline outcome Polymarket's Gamma API marks as the home team.

Input: TSV of league, event_slug, first name, second name. US leagues: a deterministic md5 sample of 50
settled full-game moneylines per league, with the market's outcome_yes and outcome_no. Soccer (rows
prefixed "soccer:"): 20 settled draw markets per competition, with the away team (second named in the
draw market title) first and the home team (first named) second.
For each event, read the Gamma event's teams[] and its `ordering` field, match the home team to the two
names, and count how often the SECOND name is the home team.
Read-only public API. Usage: python3 home-ordering.py home-ordering-sample.tsv
"""
import json, sys, time, unicodedata, urllib.request, collections

def norm(s):
    s = unicodedata.normalize("NFKD", s or "").encode("ascii", "ignore").decode().lower()
    return "".join(ch for ch in s if ch.isalnum() or ch == " ").strip()

def match(team, outcome):
    t, o = norm(team.get("name")), norm(outcome)
    alias = norm(team.get("alias"))
    return bool(t) and (t in o or o in t or (alias and (alias in o or o in alias)))

stats = collections.defaultdict(lambda: collections.Counter())
for line in open(sys.argv[1]):
    prefix, slug, o0, o1 = line.rstrip("\n").split("\t")
    try:
        # Gamma answers 403 to Python's default User-Agent; send a plain client name.
        req = urllib.request.Request(f"https://gamma-api.polymarket.com/events?slug={slug}", headers={"User-Agent": "0xinsider-research/1.0"})
        with urllib.request.urlopen(req, timeout=20) as r:
            ev = json.load(r)
    except Exception as e:  # network failure is counted, never hidden
        stats[prefix]["fetch_error"] += 1
        continue
    teams = (ev[0].get("teams") if ev else None) or []
    home = [t for t in teams if t.get("ordering") == "home"]
    if len(teams) != 2 or len(home) != 1:
        stats[prefix]["no_ordering"] += 1
        continue
    h = home[0]
    if match(h, o1) and not match(h, o0):
        stats[prefix]["second_outcome_home_by_name"] += 1
    elif match(h, o0) and not match(h, o1):
        stats[prefix]["first_outcome_home_by_name"] += 1
    else:
        # names do not identify the team (college mascots); fall back to array position
        key = "second_outcome_home_by_position" if teams[1].get("ordering") == "home" else "first_outcome_home_by_position"
        stats[prefix][key] += 1
    time.sleep(0.15)

for prefix in sorted(stats):
    print(prefix, dict(stats[prefix]))
