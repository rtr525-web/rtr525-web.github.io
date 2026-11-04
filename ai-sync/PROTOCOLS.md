# Connection Protocols

1. **Source of truth:** `ai-sync/context.json`. Every AI fetches it first (see `connect.txt`).
2. **Health file:** `ai-sync/status.json`, rewritten by the Connection Spooler.
   - `LIVE` = all pages return 200 and the feed is under 36 h old.
   - `STALE` = pages up but feed older than 36 h → Muse refreshes the feed.
   - `DEGRADED` = a page or JSON file is missing, malformed, or not returning 200.
3. **Spooler cadence:** GitHub Action `Connection Spooler` runs every 2 h, on every push
   to `main`, and on demand (Actions tab → Run workflow). A red run means a page is broken.
4. **Local check:** `python3 tools/spooler.py` (add `--live` to test the public URLs).
5. **Publishing gate:** unchanged — Muse/Robert are the only publishers; the spooler only
   reads pages and writes `status.json`.
