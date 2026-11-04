#!/usr/bin/env python3
"""Connection spooler: checks every Empire page + feed, writes ai-sync/status.json.
Read-only against the outside world; only writes the status file in this repo."""
import json, sys, re, urllib.request, datetime, pathlib
ROOT = pathlib.Path(__file__).resolve().parent.parent
BASE = "https://rtr525-web.github.io/"
PAGES = ["", "ai-sync/", "ai-sync/context.json", "ai-sync/connect.txt",
         "empire/", "empire/approvals.json", "empire/messages.json",
         "today/", "topics/", "drive-desk/", "manifest.webmanifest"]
STALE_HOURS = 36

def local_checks():
    out = []
    for p in PAGES:
        f = ROOT / (p + "index.html" if p.endswith("/") or p == "" else p)
        ok = f.exists()
        if ok and f.suffix in (".json", ".webmanifest"):
            try: json.loads(f.read_text())
            except Exception as e: ok = False; out.append({"path": p, "local": f"BAD JSON: {e}"}); continue
        out.append({"path": p, "local": "ok" if ok else "MISSING"})
    return out

def live(path):
    try:
        with urllib.request.urlopen(urllib.request.Request(BASE + path, headers={"User-Agent": "empire-spooler"}), timeout=20) as r:
            return r.status
    except urllib.error.HTTPError as e: return e.code
    except Exception: return 0

def main():
    now = datetime.datetime.now(datetime.timezone.utc)
    checks = local_checks()
    do_live = "--live" in sys.argv
    for c in checks:
        if do_live: c["live"] = live(c["path"])
    feed = json.loads((ROOT / "ai-sync/context.json").read_text())
    stamp = feed.get("updated_at", "")
    try: age = (now - datetime.datetime.fromisoformat(stamp)).total_seconds() / 3600
    except Exception: age = None
    problems = [c for c in checks if c["local"] != "ok" or (do_live and c.get("live") != 200)]
    stale = age is None or age > STALE_HOURS
    status = {
        "checked_at": now.isoformat(timespec="seconds"),
        "overall": "LIVE" if not problems and not stale else ("STALE" if not problems else "DEGRADED"),
        "feed_updated_at": stamp,
        "feed_age_hours": round(age, 1) if age is not None else None,
        "stale_threshold_hours": STALE_HOURS,
        "empire_pages_count": len(feed.get("empire_pages", [])),
        "checks": checks,
        "problems": [c["path"] or "/" for c in problems],
    }
    (ROOT / "ai-sync/status.json").write_text(json.dumps(status, indent=2) + "\n")
    print(json.dumps({k: status[k] for k in ("overall", "feed_updated_at", "feed_age_hours", "problems")}))
    return 1 if problems else 0

if __name__ == "__main__":
    sys.exit(main())
