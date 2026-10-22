#!/bin/bash
# <xbar.title>Muse Connection</xbar.title>
# <xbar.version>1.0</xbar.version>
# <xbar.author>Muse (built for Robert)</xbar.author>
# <xbar.desc>Live menu-bar status of the Jayhil Bridge: Connected, Working, or Off — read from the Bridge's own process and files every 15 seconds.</xbar.desc>
# <xbar.dependencies>bash, pgrep, python3 (optional, for reading result details)</xbar.dependencies>
#
# Muse Connection — a SwiftBar plugin.
#
# The "15s" in this file's name is what makes SwiftBar re-run it every
# 15 seconds. Each run it looks at the Jayhil Bridge's own evidence on
# this Mac — is the Bridge process alive? is a task waiting in the
# inbox? what does status.txt say? — and prints the menu-bar title
# plus a battery-style dropdown. It changes nothing; it only reads.
#
# States (the title dot changes color, the dropdown says the word):
#   Working   (yellow) — Bridge is running AND a task is in the inbox
#   Connected (green)  — Bridge is running, inbox empty
#   Off       (red)    — Bridge is not running (its window is closed)

BRIDGE_HOME="$HOME/JayhilBridge"
TASKS_DIR="$BRIDGE_HOME/tasks"
RESULTS_DIR="$BRIDGE_HOME/results"
STATUS_FILE="$BRIDGE_HOME/status.txt"

COLOR_GREEN="#30D158"
COLOR_YELLOW="#FFD60A"
COLOR_RED="#FF453A"

# --- Gather the evidence ------------------------------------------------

# Is any Bridge window (menu or watch mode) running on this Mac?
bridge_running=0
if pgrep -f "JayhilBridge.command" >/dev/null 2>&1; then
  bridge_running=1
fi

# How many task files are waiting in the inbox? (tasks/done/ doesn't
# count — the glob only matches files directly in tasks/.)
waiting=0
if [ -d "$TASKS_DIR" ]; then
  for f in "$TASKS_DIR"/*.json; do
    [ -f "$f" ] && waiting=$((waiting + 1))
  done
fi

# What does the last self-test say? Line 1 carries the stamp; the
# check lines start with PASS or FAIL.
status_stamp=""
pass_count=""
fail_count=""
status_age_hours=""
if [ -f "$STATUS_FILE" ]; then
  first_line="$(head -n 1 "$STATUS_FILE" 2>/dev/null)"
  # Everything after the last "— " on line 1 is the date/time stamp.
  status_stamp="${first_line##*— }"
  [ "$status_stamp" = "$first_line" ] && status_stamp="$first_line"
  pass_count="$(grep -c '^PASS' "$STATUS_FILE" 2>/dev/null)"
  fail_count="$(grep -c '^FAIL' "$STATUS_FILE" 2>/dev/null)"
  [ -z "$pass_count" ] && pass_count="0"
  [ -z "$fail_count" ] && fail_count="0"
  mtime="$(stat -f %m "$STATUS_FILE" 2>/dev/null)"
  now="$(date +%s)"
  case "$mtime" in
    ''|*[!0-9]*) mtime="" ;;
  esac
  if [ -n "$mtime" ]; then
    status_age_hours=$(( (now - mtime) / 3600 ))
  fi
fi

# The newest result file, and a plain-English summary of it.
latest_result=""
latest_mtime=0
if [ -d "$RESULTS_DIR" ]; then
  for f in "$RESULTS_DIR"/*.json; do
    [ -f "$f" ] || continue
    m="$(stat -f %m "$f" 2>/dev/null)"
    case "$m" in ''|*[!0-9]*) m=0 ;; esac
    if [ "$m" -ge "$latest_mtime" ]; then
      latest_mtime="$m"
      latest_result="$f"
    fi
  done
fi

last_job_line=""
if [ -n "$latest_result" ]; then
  if command -v python3 >/dev/null 2>&1; then
    last_job_line="$(python3 - "$latest_result" <<'PYEOF' 2>/dev/null
import json, sys
try:
    with open(sys.argv[1]) as fh:
        d = json.load(fh)
    print("Last job: %s - %s - %s" % (
        d.get("task", "?"), d.get("status", "?"), d.get("finished_at", "?")))
except Exception:
    pass
PYEOF
)"
  fi
  # No python3, or the file didn't parse: fall back to the file name.
  if [ -z "$last_job_line" ]; then
    last_job_line="Last job: $(basename "$latest_result")"
  fi
fi

# Where is the Bridge script itself? "Start" / "Self-Test" dropdown
# actions need the real path — Robert's copy was downloaded, so check
# Downloads first, then Desktop.
bridge_script=""
for cand in "$HOME/Downloads/JayhilBridge.command" "$HOME/Desktop/JayhilBridge.command"; do
  if [ -f "$cand" ]; then
    bridge_script="$cand"
    break
  fi
done

# --- Decide the state ----------------------------------------------------
# The running process is the ground truth. Task files alone never make
# it "Working" — if the Bridge is closed, waiting tasks are stuck, and
# the icon must say Off (the dropdown explains the stuck tasks).

if [ "$bridge_running" -eq 1 ] && [ "$waiting" -gt 0 ]; then
  state="Working"
  color="$COLOR_YELLOW"
elif [ "$bridge_running" -eq 1 ]; then
  state="Connected"
  color="$COLOR_GREEN"
else
  state="Off"
  color="$COLOR_RED"
fi

# --- Print the menu ------------------------------------------------------

# Title (the part that lives in the menu bar, next to Wi-Fi/battery).
echo "Muse ● | color=$color"

echo "---"

# Line 1 — the state, in words.
echo "Muse Connection — $state | color=$color"

# Line 2 — the Bridge's last self-test, from status.txt.
if [ -n "$status_stamp" ]; then
  checks_line="Bridge: $pass_count checks PASS"
  [ "$fail_count" != "0" ] && checks_line="$checks_line, $fail_count FAIL"
  checks_line="$checks_line · self-test $status_stamp"
  # Honest staleness flag: a self-test older than a day gets labeled.
  if [ -n "$status_age_hours" ] && [ "$status_age_hours" -ge 24 ]; then
    checks_line="$checks_line (old — run Self-Test below)"
  fi
  echo "$checks_line"
else
  echo "Bridge: no self-test on file yet"
fi

# Line 3 — the most recent finished job, if any.
if [ -n "$last_job_line" ]; then
  echo "$last_job_line"
fi

# Line 4 — inbox count. Wording changes with the state so it never
# claims work is happening when the Bridge is closed.
if [ "$waiting" -gt 0 ]; then
  if [ "$bridge_running" -eq 1 ]; then
    echo "Waiting in inbox: $waiting"
  else
    echo "Waiting in inbox: $waiting — stuck, the Bridge is off"
  fi
else
  echo "Waiting in inbox: 0"
fi

echo "---"

# Actions.
if [ -n "$bridge_script" ]; then
  echo "Start the Bridge | bash=/bin/bash param0=\"$bridge_script\" param1=--watch terminal=true refresh=true"
  echo "Run Self-Test | bash=/bin/bash param0=\"$bridge_script\" param1=--selftest terminal=true refresh=true"
else
  echo "Bridge script not found in Downloads or Desktop | color=$COLOR_RED"
fi
echo "Open Bridge Folder | bash=/usr/bin/open param0=\"$BRIDGE_HOME\" terminal=false"
if [ -n "$latest_result" ]; then
  echo "Open Latest Result | bash=/usr/bin/open param0=\"$latest_result\" terminal=false"
fi
echo "Refresh | refresh=true"
