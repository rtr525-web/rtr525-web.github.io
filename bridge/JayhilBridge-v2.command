#!/bin/bash
# =============================================================================
# Jayhil Bridge — a small helper that runs on Robert's Mac.
#
# What it does: it gives Muse a safe way to finish jobs that can't be done
# from Muse's own computer — things like putting photos into Apple Photos,
# helping with a Google Photos upload, archiving Instagram posts, and
# emptying the Trash.
#
# Safety, in plain words:
#   * It NEVER reads, stores, or types any password. Not yours, not anyone's.
#   * It never runs commands sent from somewhere else. The "watch mode" below
#     only accepts a short list of known, safe task types — anything else is
#     refused and written to the log.
#   * Anything destructive (emptying the Trash, archiving a post) asks you
#     on-screen first, once per session.
#   * Two watch-mode jobs skip that ask on purpose, because both are easy
#     to undo: tidying the Dock (your current Dock is backed up first, to
#     logs/dock-backup-*.txt) and setting the desktop wallpaper.
#
# Version 2 (Oct 22, 2026) — adds the dock_cleanup and set_wallpaper task
# types. Every v1 job and safety rule still works exactly as before.
#
# How to run: double-click this file. If macOS blocks it the first time,
# right-click the file and choose "Open".
# =============================================================================

# ---------------------------------------------------------------------------
# Settings you can change
# ---------------------------------------------------------------------------
# Default folder used by the photo menu items if you don't pick one.
# The two Instagram archive folders are checked first if they exist.
DEFAULT_PHOTOS_FOLDER="$HOME/Downloads"
IG_ARCHIVE_FOLDERS=(
  "$HOME/workspace/your_files/ig-archive-winterparkroad-2026-10-22"
  "$HOME/workspace/your_files/ig-archive-mrhillsboro-2026-10-22"
)

BRIDGE_HOME="$HOME/JayhilBridge"
TASKS_DIR="$BRIDGE_HOME/tasks"
RESULTS_DIR="$BRIDGE_HOME/results"
LOGS_DIR="$BRIDGE_HOME/logs"
STATUS_FILE="$BRIDGE_HOME/status.txt"
LOG_FILE="$LOGS_DIR/bridge.log"

# Session flags: destructive actions ask once per session, then remember.
CONFIRMED_TRASH=0
CONFIRMED_ARCHIVE=0

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------
log_line() {
  # Write a timestamped line to the bridge log (and make sure folders exist).
  mkdir -p "$LOGS_DIR"
  printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG_FILE"
}

say_box() {
  # Show a simple on-screen message box. Falls back to the terminal.
  /usr/bin/osascript -e "display dialog \"$1\" buttons {\"OK\"} default button \"OK\" with title \"Jayhil Bridge\"" >/dev/null 2>&1 \
    || printf '%s\n' "$1"
}

ask_yes_no() {
  # Ask an on-screen Yes/No question. Returns 0 for Yes, 1 for No.
  # If the dialog can't be shown, fall back to typing in the terminal.
  local answer
  answer=$(/usr/bin/osascript -e "button returned of (display dialog \"$1\" buttons {\"No\", \"Yes\"} default button \"No\" with title \"Jayhil Bridge\")" 2>/dev/null)
  if [ -n "$answer" ]; then
    [ "$answer" = "Yes" ]
    return
  fi
  printf '%s [y/N] ' "$1"
  read -r answer
  [ "$answer" = "y" ] || [ "$answer" = "Y" ]
}

pick_folder() {
  # Let the user choose a folder with the normal macOS picker.
  # Prints the chosen path, or nothing if they cancel.
  /usr/bin/osascript -e 'POSIX path of (choose folder with prompt "Pick the folder of photos and videos")' 2>/dev/null
}

first_existing_ig_folder() {
  # Print the first Instagram archive folder that exists, if any.
  local f
  for f in "${IG_ARCHIVE_FOLDERS[@]}"; do
    if [ -d "$f" ]; then
      printf '%s' "$f"
      return 0
    fi
  done
  return 1
}

# ---------------------------------------------------------------------------
# Self-test — checks this Mac has what the bridge needs, writes status.txt
# ---------------------------------------------------------------------------
run_selftest() {
  mkdir -p "$TASKS_DIR" "$RESULTS_DIR" "$LOGS_DIR"
  local lines=()
  local stamp
  stamp="$(date '+%Y-%m-%d %H:%M:%S %Z')"

  lines+=("Jayhil Bridge status — $stamp")
  lines+=("Computer: $(/usr/bin/sw_vers -productName 2>/dev/null) $(/usr/bin/sw_vers -productVersion 2>/dev/null)")

  # macOS check
  if [ "$(uname -s)" = "Darwin" ]; then
    lines+=("PASS  macOS detected")
  else
    lines+=("FAIL  This does not look like macOS — the bridge only runs on your Mac")
  fi

  # python3 check (watch mode uses it to read task files safely)
  if command -v python3 >/dev/null 2>&1; then
    lines+=("PASS  python3 found ($(python3 --version 2>&1))")
  else
    lines+=("FAIL  python3 not found — install Apple's Command Line Tools: xcode-select --install")
  fi

  # Chrome check
  if [ -d "/Applications/Google Chrome.app" ]; then
    lines+=("PASS  Google Chrome is installed")
  else
    lines+=("FAIL  Google Chrome not found in /Applications")
  fi

  # Photos check
  if [ -d "/Applications/Photos.app" ] || [ -d "/System/Applications/Photos.app" ]; then
    lines+=("PASS  Apple Photos is installed")
  else
    lines+=("FAIL  Apple Photos app not found")
  fi

  # Dock check (v2 — the dock_cleanup task reads this same list)
  local dock_count
  dock_count="$(/usr/bin/defaults read com.apple.dock persistent-apps 2>/dev/null | grep -c 'file-label')"
  if [ -n "$dock_count" ] && [ "$dock_count" != "0" ]; then
    lines+=("PASS  Dock list read — $dock_count app(s) pinned in the Dock")
  else
    lines+=("FAIL  Could not read the Dock app list (dock_cleanup would stop safely)")
  fi

  # Bridge folders
  if [ -d "$TASKS_DIR" ] && [ -d "$RESULTS_DIR" ] && [ -d "$LOGS_DIR" ]; then
    lines+=("PASS  Bridge folders ready in $BRIDGE_HOME")
  else
    lines+=("FAIL  Could not create bridge folders in $BRIDGE_HOME")
  fi

  printf '%s\n' "${lines[@]}" | tee "$STATUS_FILE"
  log_line "Self-test written to status.txt"
}

write_status_file() {
  # Used by the watch-mode "write_status" task: refresh status.txt.
  run_selftest >/dev/null
}

# ---------------------------------------------------------------------------
# Action 1 — Import a folder into Apple Photos
# Drives the Photos app with AppleScript and imports every image/video file
# in the chosen folder. Photos itself handles duplicates the usual way.
# ---------------------------------------------------------------------------
apple_photos_import() {
  local folder="$1"
  if [ -z "$folder" ] || [ ! -d "$folder" ]; then
    log_line "apple_photos_import: folder missing or not a folder: '$folder'"
    printf 'That folder does not exist: %s\n' "$folder"
    return 1
  fi
  log_line "apple_photos_import: importing from $folder"
  /usr/bin/osascript - "$folder" <<'APPLESCRIPT'
on run argv
  set theFolder to item 1 of argv
  tell application "Finder"
    set theFiles to every file of folder (theFolder as POSIX file) ¬
      whose name extension is in {"jpg", "jpeg", "png", "heic", "heif", "gif", "tif", "tiff", "webp", "bmp", "mov", "mp4", "m4v", "avi"}
  end tell
  if (count of theFiles) is 0 then
    display dialog "No photos or videos found in that folder." buttons {"OK"} default button "OK" with title "Jayhil Bridge"
    return "none"
  end if
  set fileList to {}
  repeat with f in theFiles
    set end of fileList to (f as alias)
  end repeat
  tell application "Photos"
    activate
    import fileList skip check duplicates no
  end tell
  return (count of fileList) as text
end run
APPLESCRIPT
  local rc=$?
  if [ $rc -eq 0 ]; then
    log_line "apple_photos_import: Photos accepted the import from $folder"
  else
    log_line "apple_photos_import: AppleScript returned an error for $folder"
  fi
  return $rc
}

# ---------------------------------------------------------------------------
# Action 2 — Google Photos upload assist (semi-automated ON PURPOSE)
# Google does not offer a supported way for a script to add photos to a
# personal Google Photos library, so this does NOT pretend to. It opens the
# folder in Finder and the Google Photos upload page in Chrome, side by side,
# and tells you exactly what to drag where.
# ---------------------------------------------------------------------------
google_photos_assist() {
  local folder="$1"
  if [ -z "$folder" ] || [ ! -d "$folder" ]; then
    folder="$(pick_folder)"
    [ -n "$folder" ] || return 1
  fi
  log_line "google_photos_assist: opening folder $folder and the upload page"
  /usr/bin/open "$folder"
  /usr/bin/open -a "Google Chrome" "https://photos.google.com/upload"
  say_box "Two windows are open: your folder, and Google Photos in Chrome.\n\n1. In Chrome, make sure you are signed in to the right Google account.\n2. Drag the photos/videos from the folder window into the Chrome upload page (or click Upload > Computer on that page and pick the files).\n3. Wait until Google Photos says the upload finished before closing Chrome."
}

# ---------------------------------------------------------------------------
# Action 3 — Instagram archive runner
# Reads post URLs (one per line) from a list file, opens each in Chrome, and
# tries to click the post's "..." (More options) menu and then "Archive"
# using JavaScript run through AppleScript.
#
# IMPORTANT: Chrome only allows this if you first turn on:
#   Chrome menu: View > Developer > Allow JavaScript from Apple Events
# If that is off (or Instagram has changed its page layout), the runner
# degrades gracefully: it opens each post one at a time and asks you to tap
# "..." > "Archive" yourself, then waits for you to say "Next".
#
# Note: Instagram only shows "Archive" on YOUR OWN posts, and only while you
# are signed in as the account that posted them.
# ---------------------------------------------------------------------------
confirm_archive_once() {
  if [ "$CONFIRMED_ARCHIVE" -eq 0 ]; then
    if ask_yes_no "The archive runner will open each post and archive it on your Instagram account. Archiving hides a post from your profile — it does NOT delete it, and you can un-archive later. Continue?"; then
      CONFIRMED_ARCHIVE=1
    else
      return 1
    fi
  fi
  return 0
}

ig_archive_one() {
  # Open one post URL in Chrome and try the JavaScript menu click.
  local url="$1"
  log_line "ig_archive: opening $url"
  /usr/bin/open -a "Google Chrome" "$url"
  sleep 4   # let the page load

  local result
  result=$(/usr/bin/osascript <<'APPLESCRIPT' 2>/dev/null
tell application "Google Chrome"
  if not (exists window 1) then return "no-window"
  set jsCode to "(function(){var b=document.querySelector('svg[aria-label=\"More options\"]');if(!b){return 'no-menu';}var btn=b.closest('button,[role=button]');(btn||b).click();return 'menu-opened';})()"
  try
    set r to execute javascript jsCode in active tab of window 1
  on error
    return "js-blocked"
  end try
  return r
end tell
APPLESCRIPT
)
  if [ "$result" = "menu-opened" ]; then
    sleep 2
    local result2
    result2=$(/usr/bin/osascript <<'APPLESCRIPT' 2>/dev/null
tell application "Google Chrome"
  set jsCode to "(function(){var els=document.querySelectorAll('button,[role=button],[role=menuitem]');for(var i=0;i<els.length;i++){if(els[i].textContent.trim()==='Archive'){els[i].click();return 'archived';}}return 'no-archive-item';})()"
  try
    set r to execute javascript jsCode in active tab of window 1
  on error
    return "js-blocked"
  end try
  return r
end tell
APPLESCRIPT
)
    if [ "$result2" = "archived" ]; then
      log_line "ig_archive: archived via menu click: $url"
      printf 'Archived: %s\n' "$url"
      return 0
    fi
    log_line "ig_archive: menu opened but no Archive item found for $url (result: $result2)"
  else
    log_line "ig_archive: automatic click unavailable for $url (result: $result)"
  fi

  # Graceful fallback: walk the user through it by hand.
  say_box "This post is open in Chrome:\n$url\n\nAutomatic clicking didn't work for this one (Chrome may need: View > Developer > Allow JavaScript from Apple Events — or Instagram changed its layout).\n\nPlease click the ... menu on the post, then Archive, then press OK here for the next one."
  return 2
}

ig_archive_run() {
  # $1 = list file (defaults to ~/JayhilBridge/tasks/ig-archive.txt)
  local list_file="${1:-$TASKS_DIR/ig-archive.txt}"
  if [ ! -f "$list_file" ]; then
    say_box "No archive list found at:\n$list_file\n\nCreate that file with one Instagram post address per line, then run this again."
    log_line "ig_archive: list file missing: $list_file"
    return 1
  fi
  confirm_archive_once || { log_line "ig_archive: user declined at confirm"; return 1; }

  local url done_count=0 fail_count=0
  while IFS= read -r url || [ -n "$url" ]; do
    # Skip blank lines and comments.
    case "$url" in ''|\#*) continue ;; esac
    if ig_archive_one "$url"; then
      done_count=$((done_count+1))
    else
      fail_count=$((fail_count+1))
    fi
    sleep 1
  done < "$list_file"
  log_line "ig_archive: finished. archived=$done_count needs-attention=$fail_count"
  say_box "Archive run finished.\nArchived: $done_count\nNeeded a hand: $fail_count\n\nDetails are in the bridge log."
}

# ---------------------------------------------------------------------------
# Action 4 — Empty the Trash
# Asks first (once per session), then asks Finder to empty the Trash.
# ---------------------------------------------------------------------------
empty_trash() {
  if [ "$CONFIRMED_TRASH" -eq 0 ]; then
    if ask_yes_no "Empty the Trash? Files in the Trash will be permanently deleted. This cannot be undone."; then
      CONFIRMED_TRASH=1
    else
      log_line "empty_trash: user declined at confirm"
      return 1
    fi
  fi
  /usr/bin/osascript -e 'tell application "Finder" to empty trash' 2>/dev/null
  local rc=$?
  if [ $rc -eq 0 ]; then
    log_line "empty_trash: Trash emptied"
    printf 'Trash emptied.\n'
  else
    log_line "empty_trash: Finder returned an error"
    printf 'Finder could not empty the Trash (it may already be empty).\n'
  fi
  return $rc
}

# ---------------------------------------------------------------------------
# Action 5 (v2) — Tidy the Dock
# Rebuilds the Dock's pinned-apps list, keeping ONLY the apps named in the
# task (or a sensible default set). Runs WITHOUT an on-screen prompt in
# watch mode — on purpose: the change is fully reversible, because the very
# first step saves a backup of the current list:
#   logs/dock-backup-<timestamp>.txt    the list in readable form
#   logs/dock-backup-<timestamp>.plist  the whole Dock settings, restorable
# Restore = defaults import the .plist backup, then killall Dock
# (exact steps are in the README's v2 section).
#
# Finder and the Trash are never touched: Finder is managed by macOS
# itself (and is always kept if it appears in the list at all), and the
# Trash lives in persistent-others, which this function never reads or
# writes. Only persistent-apps is rebuilt, and every kept app keeps its
# full original settings entry — python's plistlib does that work so
# nothing is retyped or guessed at.
#
# Fail-safe: if the current list can't be read, or keeping only the named
# apps would leave the Dock empty, NOTHING is changed and the task ends
# with status "error".
# ---------------------------------------------------------------------------
dock_cleanup_task() {
  # $1 = task file. Prints exactly one detail line; exit 0 = Dock tidied.
  local file="$1"

  # The keep list from the task file; the default set if the task names none.
  local keep_items=() k
  while IFS= read -r k; do
    [ -n "$k" ] && keep_items+=("$k")
  done <<EOF
$(task_field "$file" keep)
EOF
  if [ "${#keep_items[@]}" -eq 0 ]; then
    keep_items=(Finder Muse "Google Chrome" Photos "System Settings")
  fi

  # Step 1 — back up the current Dock list BEFORE changing anything.
  mkdir -p "$LOGS_DIR"
  local stamp backup_txt backup_plist
  stamp="$(date '+%Y%m%d-%H%M%S')-$$"
  backup_txt="$LOGS_DIR/dock-backup-$stamp.txt"
  backup_plist="$LOGS_DIR/dock-backup-$stamp.plist"
  if ! /usr/bin/defaults read com.apple.dock persistent-apps > "$backup_txt" 2>/dev/null || [ ! -s "$backup_txt" ]; then
    log_line "dock_cleanup: could not read the current Dock list — aborted, Dock unchanged"
    printf 'Dock cleanup stopped: the current Dock list could not be read, so nothing was changed.'
    return 1
  fi
  # A restorable copy of the whole Dock settings, same timestamp.
  /usr/bin/defaults export com.apple.dock "$backup_plist" >/dev/null 2>&1 || true
  log_line "dock_cleanup: backed up the Dock list to $backup_txt"

  # Step 2 — python works out what stays and what goes, and writes the
  # rebuilt Dock settings to a temp plist. Nothing is applied yet.
  local tmp_plist plan p_status p_kept p_removed p_msg
  tmp_plist="$LOGS_DIR/.dock-plan-$stamp.plist"
  plan="$(python3 - "$tmp_plist" "${keep_items[@]}" <<'PYEOF'
import plistlib, subprocess, sys

out_path = sys.argv[1]
keep = set()
for raw in sys.argv[2:]:
    name = raw.strip().lower()
    if name:
        keep.add(name)
if not keep:
    print("STATUS=error")
    print("MSG=No keep list was given.")
    sys.exit(0)

def entry_name(entry):
    """The app name for one Dock entry: its label, else its .app name."""
    if not isinstance(entry, dict):
        return ""
    tile = entry.get("tile-data", {})
    if not isinstance(tile, dict):
        return ""
    label = tile.get("file-label")
    if isinstance(label, str) and label:
        return label
    fdata = tile.get("file-data", {})
    if isinstance(fdata, dict):
        url = fdata.get("_CFURLString", "")
        if isinstance(url, str) and url:
            base = url.rstrip("/").rsplit("/", 1)[-1]
            if base.endswith(".app"):
                base = base[:-4]
            return base
    return ""

try:
    raw = subprocess.check_output(
        ["/usr/bin/defaults", "export", "com.apple.dock", "-"])
    data = plistlib.loads(raw)
except Exception as exc:
    print("STATUS=error")
    print("MSG=Could not read the Dock settings (%s)." % exc)
    sys.exit(0)

apps = data.get("persistent-apps", [])
kept, kept_names, removed_names = [], [], []
for entry in apps:
    name = entry_name(entry)
    # Finder is system-managed — it is never removed, whatever the list says.
    if name.lower() == "finder" or name.lower() in keep:
        kept.append(entry)
        kept_names.append(name if name else "Finder")
    else:
        removed_names.append(name if name else "(unnamed tile)")

if not kept:
    print("STATUS=error")
    print("MSG=Keeping only the named apps would leave the Dock empty.")
    sys.exit(0)

data["persistent-apps"] = kept
try:
    with open(out_path, "wb") as fh:
        plistlib.dump(data, fh, fmt=plistlib.FMT_XML)
except Exception as exc:
    print("STATUS=error")
    print("MSG=Could not prepare the new Dock list (%s)." % exc)
    sys.exit(0)

print("STATUS=done")
print("KEPT=" + ", ".join(kept_names))
print("REMOVED=" + (", ".join(removed_names) if removed_names else "none"))
PYEOF
)"
  p_status="$(printf '%s\n' "$plan" | sed -n 's/^STATUS=//p' | head -n 1)"
  p_kept="$(printf '%s\n' "$plan" | sed -n 's/^KEPT=//p' | head -n 1)"
  p_removed="$(printf '%s\n' "$plan" | sed -n 's/^REMOVED=//p' | head -n 1)"
  p_msg="$(printf '%s\n' "$plan" | sed -n 's/^MSG=//p' | head -n 1)"

  if [ "$p_status" != "done" ]; then
    rm -f "$tmp_plist"
    log_line "dock_cleanup: aborted — $p_msg (Dock unchanged; backup at $backup_txt)"
    printf 'Dock cleanup stopped: %s Nothing was changed. Backup of the current Dock: %s' "$p_msg" "$backup_txt"
    return 1
  fi

  # Step 3 — apply the rebuilt list and restart the Dock so it shows.
  if ! /usr/bin/defaults import com.apple.dock "$tmp_plist" >/dev/null 2>&1; then
    rm -f "$tmp_plist"
    log_line "dock_cleanup: defaults import failed — Dock unchanged"
    printf 'Dock cleanup failed while saving the new list — nothing was changed. Backup: %s' "$backup_txt"
    return 1
  fi
  rm -f "$tmp_plist"
  /usr/bin/killall Dock >/dev/null 2>&1 || true
  log_line "dock_cleanup: kept [$p_kept] removed [$p_removed] backup $backup_txt"
  printf 'Dock tidied. Kept: %s. Removed: %s. Backup: %s' "$p_kept" "$p_removed" "$backup_txt"
  return 0
}

# ---------------------------------------------------------------------------
# Action 6 (v2) — Set the desktop wallpaper
# Sets the desktop picture on EVERY desktop/space. Runs without an
# on-screen prompt in watch mode — it's just a picture change, undone by
# picking another picture. The file must exist and really be an image
# (checked by extension AND by the `file` tool's content sniff).
# This function never reads or sends the picture itself — it only hands
# the path to System Events.
# ---------------------------------------------------------------------------
set_wallpaper_task() {
  # $1 = task file. Prints exactly one detail line; exit 0 = wallpaper set.
  local file="$1" path ext mime
  path="$(task_field "$file" path)"
  if [ -z "$path" ]; then
    log_line "set_wallpaper: task had no image path"
    printf 'set_wallpaper task had no image path.'
    return 1
  fi
  if [ ! -f "$path" ]; then
    log_line "set_wallpaper: file not found: $path"
    printf 'Image file not found: %s' "$path"
    return 1
  fi
  ext="$(printf '%s' "${path##*.}" | tr '[:upper:]' '[:lower:]')"
  case "$ext" in
    jpg|jpeg|png|heic|tif|tiff) ;;
    *)
      log_line "set_wallpaper: unsupported image type .$ext: $path"
      printf 'Not a supported image type (.%s): %s' "$ext" "$path"
      return 1
      ;;
  esac
  if [ -x /usr/bin/file ]; then
    mime="$(/usr/bin/file -b --mime-type "$path" 2>/dev/null)"
    case "$mime" in
      image/*) ;;
      *)
        log_line "set_wallpaper: content check says '$mime', not an image: $path"
        printf 'That file does not look like an image (%s): %s' "$mime" "$path"
        return 1
        ;;
    esac
  fi
  if /usr/bin/osascript - "$path" >/dev/null 2>&1 <<'APPLESCRIPT'
on run argv
  set thePath to item 1 of argv
  set imgAlias to (POSIX file thePath) as alias
  tell application "System Events"
    repeat with d in desktops
      set picture of d to imgAlias
    end repeat
  end tell
end run
APPLESCRIPT
  then
    log_line "set_wallpaper: desktop picture set to $path"
    printf 'Wallpaper set on all desktops: %s' "$path"
    return 0
  fi
  log_line "set_wallpaper: System Events could not set the picture: $path"
  printf 'Could not set the wallpaper (System Events error): %s' "$path"
  return 1
}

# Note, by design: this script does NOT remove admin-owned apps (apps macOS
# protects with an administrator password). It only lists them in the README.
# Nothing here can type an admin password — that stays with you, always.

# ---------------------------------------------------------------------------
# Watch mode — the task inbox
# Every 15 seconds this looks in ~/JayhilBridge/tasks/ for *.json files.
# Each file must name ONE task type from the short whitelist below.
# Anything not on the list is rejected and logged — never run.
# There is deliberately NO "run a shell command" task type.
#
# Task file examples:
#   {"type": "apple_photos_import", "folder": "/Users/you/Pictures/Set1"}
#   {"type": "open_urls", "urls": ["https://photos.google.com/upload"]}
#   {"type": "ig_archive", "urls": ["https://www.instagram.com/p/XXXX/"]}
#   {"type": "empty_trash"}
#   {"type": "write_status"}
#   {"type": "dock_cleanup", "keep": ["Finder", "Muse", "Google Chrome", "Photos", "System Settings"]}
#   {"type": "set_wallpaper", "path": "/Users/you/Pictures/photo.jpg"}
#
# dock_cleanup and set_wallpaper run WITHOUT an on-screen prompt — both
# are reversible (the Dock is backed up first; a wallpaper is just a
# picture). Every other destructive type still asks first, once per
# session.
# Each handled task moves to tasks/done/ and gets a result file in results/.
# ---------------------------------------------------------------------------

# A small python helper reads a task file and prints simple KEY=VALUE lines.
# Using python's JSON parser (instead of guessing at the text) means a
# malformed or sneaky file just fails the check instead of doing damage.
task_field() {
  # $1 = task file, $2 = field name
  # String fields ("type", "folder", "path") print one line.
  # List fields ("urls", "keep") print one entry per line.
  python3 - "$1" "$2" <<'PYEOF'
import json, sys
path, field = sys.argv[1], sys.argv[2]
try:
    with open(path) as fh:
        data = json.load(fh)
except Exception as exc:
    print("__ERROR__ %s" % exc)
    sys.exit(0)
if field in ("urls", "keep"):
    values = data.get(field, [])
    if isinstance(values, list):
        for v in values:
            if isinstance(v, str):
                print(v)
else:
    val = data.get(field, "")
    print(val if isinstance(val, str) else "")
PYEOF
}

run_task_file() {
  # Execute ONE whitelisted task file. Always writes a result JSON.
  local file="$1"
  local base result_file task_type status detail
  base="$(basename "$file" .json)"
  result_file="$RESULTS_DIR/$base.result.json"
  mkdir -p "$TASKS_DIR/done"

  task_type="$(task_field "$file" type)"
  case "$task_type" in
    __ERROR__*)
      status="rejected"; detail="Task file is not valid JSON — nothing was run."
      ;;
    apple_photos_import)
      local folder
      folder="$(task_field "$file" folder)"
      if apple_photos_import "$folder"; then
        status="done"; detail="Imported folder into Apple Photos: $folder"
      else
        status="failed"; detail="Photos import did not complete for: $folder"
      fi
      ;;
    open_urls)
      local u opened=0
      while IFS= read -r u; do
        [ -n "$u" ] || continue
        case "$u" in
          http://*|https://*)
            /usr/bin/open "$u" && opened=$((opened+1))
            ;;
          *)
            log_line "open_urls: skipped non-web address: $u"
            ;;
        esac
      done <<EOF
$(task_field "$file" urls)
EOF
      status="done"; detail="Opened $opened web address(es)."
      ;;
    ig_archive)
      local tmp_list="$TASKS_DIR/.ig-archive-from-task.txt"
      task_field "$file" urls > "$tmp_list"
      if [ -s "$tmp_list" ]; then
        ig_archive_run "$tmp_list"
        status="done"; detail="Instagram archive run completed (see bridge log)."
      else
        status="failed"; detail="ig_archive task had no URLs."
      fi
      rm -f "$tmp_list"
      ;;
    empty_trash)
      if empty_trash; then
        status="done"; detail="Trash emptied."
      else
        status="failed"; detail="Trash was not emptied (declined or Finder error)."
      fi
      ;;
    write_status)
      write_status_file
      status="done"; detail="status.txt refreshed."
      ;;
    dock_cleanup)
      local dock_detail dock_rc
      dock_detail="$(dock_cleanup_task "$file")"; dock_rc=$?
      if [ $dock_rc -eq 0 ]; then
        status="done"; detail="$dock_detail"
      else
        status="error"; detail="$dock_detail"
      fi
      ;;
    set_wallpaper)
      local wp_detail wp_rc
      wp_detail="$(set_wallpaper_task "$file")"; wp_rc=$?
      if [ $wp_rc -eq 0 ]; then
        status="done"; detail="$wp_detail"
      else
        status="failed"; detail="$wp_detail"
      fi
      ;;
    "" )
      status="rejected"; detail="Task file has no type — nothing was run."
      ;;
    *)
      status="rejected"; detail="Unknown task type '$task_type' — refused by design."
      ;;
  esac

  # Write the result file, then move the task out of the inbox.
  python3 - "$result_file" "$base" "$task_type" "$status" "$detail" <<'PYEOF'
import json, sys, time
out, name, ttype, status, detail = sys.argv[1:6]
record = {"task": name, "type": ttype, "status": status,
          "detail": detail, "finished_at": time.strftime("%Y-%m-%d %H:%M:%S %Z")}
with open(out, "w") as fh:
    json.dump(record, fh, indent=2)
PYEOF
  mv "$file" "$TASKS_DIR/done/" 2>/dev/null
  log_line "task '$base' ($task_type): $status — $detail"
}

watch_mode() {
  mkdir -p "$TASKS_DIR" "$RESULTS_DIR" "$LOGS_DIR"
  printf 'Jayhil Bridge watch mode is running.\n'
  printf 'Watching %s every 15 seconds. Press Ctrl+C (or close this window) to stop.\n' "$TASKS_DIR"
  log_line "watch_mode: started"
  while true; do
    local f
    for f in "$TASKS_DIR"/*.json; do
      [ -e "$f" ] || continue
      run_task_file "$f"
    done
    sleep 15
  done
}

# ---------------------------------------------------------------------------
# The menu (what you see when you double-click)
# ---------------------------------------------------------------------------
show_menu() {
  run_selftest
  echo
  echo "=============================================================="
  echo "  JAYHIL BRIDGE"
  echo "  A helper for Muse, running on your Mac."
  echo "=============================================================="
  while true; do
    cat <<'MENU'

What would you like to do?

  1) Import a folder into Apple Photos
  2) Google Photos upload assist (opens folder + upload page)
  3) Instagram archive runner (uses tasks/ig-archive.txt)
  4) Empty the Trash
  5) Watch mode — let Muse send tasks to the inbox folder
  0) Quit

MENU
    printf 'Type a number and press Enter: '
    read -r choice
    case "$choice" in
      1)
        local folder
        folder="$(first_existing_ig_folder || true)"
        if [ -n "$folder" ]; then
          printf 'Found an Instagram archive folder:\n  %s\n' "$folder"
          if ask_yes_no "Import this folder into Apple Photos? (No = pick a different folder)"; then
            apple_photos_import "$folder"
          else
            folder="$(pick_folder)"
            [ -n "$folder" ] && apple_photos_import "$folder"
          fi
        else
          folder="$(pick_folder)"
          [ -n "$folder" ] && apple_photos_import "$folder"
        fi
        ;;
      2)
        google_photos_assist "$DEFAULT_PHOTOS_FOLDER"
        ;;
      3)
        ig_archive_run
        ;;
      4)
        empty_trash
        ;;
      5)
        watch_mode
        ;;
      0|q|Q|"")
        echo "Bye."
        break
        ;;
      *)
        echo "Please type 1, 2, 3, 4, 5, or 0."
        ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# How the script starts
#   Double-click / no arguments  -> self-test, then the menu
#   --watch                      -> watch mode (headless)
#   --selftest                   -> self-test only
#   --run <task.json>            -> run one whitelisted task file (headless)
#   --photos <folder>            -> import a folder into Apple Photos
#   --trash                      -> empty the Trash (still asks first)
# ---------------------------------------------------------------------------
main() {
  mkdir -p "$TASKS_DIR" "$RESULTS_DIR" "$LOGS_DIR"
  case "${1:-}" in
    --watch)
      run_selftest >/dev/null
      watch_mode
      ;;
    --selftest)
      run_selftest
      ;;
    --run)
      [ -n "${2:-}" ] && run_task_file "$2"
      ;;
    --photos)
      apple_photos_import "${2:-}"
      ;;
    --trash)
      empty_trash
      ;;
    *)
      show_menu
      ;;
  esac
}

main "$@"
