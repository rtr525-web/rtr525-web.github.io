#!/bin/bash
# =============================================================================
# RunClaudeCode.command — Jayhil Bridge launcher for Claude Code
#
# What this does: runs ONE Claude Code job, non-interactively, inside a
# single work folder on Robert's Mac, and saves the full transcript.
#
#   Work folder (the ONLY place Claude Code starts in):
#     ~/JayhilBridge/claude-code-jobs/
#   Jobs can be queued as notes in:
#     ~/JayhilBridge/messages/to-claude-code/     (oldest *.md runs first)
#   Transcripts land in:
#     ~/JayhilBridge/results/claude-code-<YYYYMMDD-HHMM>.md
#   Handled queue notes are moved to:
#     ~/JayhilBridge/messages/archive/
#
# Safety, hard-coded — there are no flags that loosen any of this:
#   * Permission mode is "acceptEdits": Claude Code may edit files inside
#     the work folder without asking, and nothing more. The
#     skip-all-permissions mode is NEVER used, and there is no
#     full-auto flag.
#   * Every run is capped at 40 turns.
#   * This script never installs anything and never signs in.
#     Installing Claude Code and signing in are Robert's one-time steps,
#     done by hand in Terminal (see the README in this folder).
#
# How to run: double-click for the menu, or from Terminal:
#   ./RunClaudeCode.command                    -> menu
#   ./RunClaudeCode.command --run <file>       -> prompt from a file
#   ./RunClaudeCode.command --text "the job"   -> prompt from the argument
#   ./RunClaudeCode.command --preflight        -> checks only, no run
# =============================================================================

BRIDGE_HOME="$HOME/JayhilBridge"
WORKDIR="$BRIDGE_HOME/claude-code-jobs"
QUEUE_DIR="$BRIDGE_HOME/messages/to-claude-code"
ARCHIVE_DIR="$BRIDGE_HOME/messages/archive"
RESULTS_DIR="$BRIDGE_HOME/results"

MAX_TURNS=40
PERMISSION_MODE="acceptEdits"

CLAUDE_BIN=""

# ---------------------------------------------------------------------------
# Preflight — plain PASS/FAIL lines. Returns 0 only if a run may proceed.
# ---------------------------------------------------------------------------
run_preflight() {
  local ok=0

  # (c)+(queue) Folders first, so the checks below can rely on them.
  mkdir -p "$WORKDIR" "$QUEUE_DIR" "$ARCHIVE_DIR" "$RESULTS_DIR"

  # (a) Is the Claude Code CLI installed?
  CLAUDE_BIN=""
  if command -v claude >/dev/null 2>&1; then
    CLAUDE_BIN="$(command -v claude)"
  elif [ -x "$HOME/.claude/local/claude" ]; then
    CLAUDE_BIN="$HOME/.claude/local/claude"
  elif [ -x "/opt/homebrew/bin/claude" ]; then
    CLAUDE_BIN="/opt/homebrew/bin/claude"
  elif [ -x "/usr/local/bin/claude" ]; then
    CLAUDE_BIN="/usr/local/bin/claude"
  fi

  if [ -n "$CLAUDE_BIN" ]; then
    printf 'PASS  Claude Code found: %s\n' "$CLAUDE_BIN"
  else
    printf 'FAIL  Claude Code (the `claude` command) is not installed.\n'
    printf '\nThis script will not install anything. Two ways Robert can install it:\n'
    printf '  1) Official native installer — download it from https://claude.com/download\n'
    printf '     and run it, then open a fresh Terminal window.\n'
    if command -v npm >/dev/null 2>&1; then
      printf '  2) Node.js is on this Mac, so this also works in Terminal:\n'
      printf '       npm install -g @anthropic-ai/claude-code\n'
    else
      printf '  2) Or, with Node.js installed: npm install -g @anthropic-ai/claude-code\n'
    fi
    printf '\nInstall once, sign in once (see below), then run this script again.\n'
    ok=1
  fi

  # (b) Sign-in config — EXISTENCE only. This script never reads credential
  # values and never attempts a login.
  if [ -d "$HOME/.claude" ] && { [ -e "$HOME/.claude/.credentials.json" ] \
      || [ -e "$HOME/.claude/settings.json" ] \
      || [ -e "$HOME/.claude/config.json" ] \
      || [ -n "$(ls -A "$HOME/.claude" 2>/dev/null)" ]; }; then
    printf 'PASS  Claude Code config found in ~/.claude — if Claude Code asks you to sign in, that is Robert'\''s step, in the window.\n'
  else
    printf 'FAIL  No Claude Code config found in ~/.claude yet.\n'
    printf '      Signing in is Robert'\''s step: open Terminal, run `claude` once,\n'
    printf '      complete the sign-in it offers, quit it, then run this script again.\n'
    printf '      This script never signs in and never touches credentials.\n'
    ok=1
  fi

  # (c) Work folder.
  if [ -d "$WORKDIR" ]; then
    printf 'PASS  Work folder ready: %s\n' "$WORKDIR"
  else
    printf 'FAIL  Could not create the work folder: %s\n' "$WORKDIR"
    ok=1
  fi

  return $ok
}

# ---------------------------------------------------------------------------
# Prompt helpers
# ---------------------------------------------------------------------------

# Print a note/prompt file with any leading frontmatter block removed:
# if the first line is exactly "---", everything up to the next "---" line
# is dropped and the body below it is the prompt. No frontmatter = whole file.
prompt_from_file() {
  awk '
    NR == 1 && $0 == "---" { in_fm = 1; next }
    in_fm == 1 && $0 == "---" { in_fm = 0; next }
    in_fm == 0 { print }
  ' "$1"
}

# Oldest queued note (by modification time), or nothing.
oldest_queued_note() {
  local f
  f="$(ls -tr "$QUEUE_DIR"/*.md 2>/dev/null | head -n 1)"
  [ -n "$f" ] && [ -f "$f" ] && printf '%s' "$f"
}

# A prompt counts as empty if it has no non-space characters at all.
prompt_is_empty() {
  [ -z "$(printf '%s' "$1" | tr -d '[:space:]')" ]
}

# Read a pasted/typed job from the keyboard until a line that is only: END
read_typed_job() {
  local line prompt=""
  printf 'Type or paste the job now, line by line.\n'
  printf 'Finish with a line containing only: END\n'
  while IFS= read -r line; do
    [ "$line" = "END" ] && break
    prompt="${prompt}${line}
"
  done
  printf '%s' "$prompt"
}

# ---------------------------------------------------------------------------
# The run itself
#   $1 = prompt text   $2 = job source label   $3 = queue note path (or "")
# ---------------------------------------------------------------------------
do_run() {
  local prompt="$1" source_label="$2" queue_note="$3"

  if prompt_is_empty "$prompt"; then
    printf '\nNothing to run: the job text is empty. Refusing to start Claude Code with an empty prompt.\n'
    return 1
  fi

  local stamp result_file result_name rc finish_time
  stamp="$(date '+%Y%m%d-%H%M')"
  result_file="$RESULTS_DIR/claude-code-$stamp.md"
  # Same-minute runs must not overwrite each other.
  local n=2
  while [ -e "$result_file" ]; do
    result_file="$RESULTS_DIR/claude-code-$stamp-$n.md"
    n=$((n + 1))
  done
  result_name="$(basename "$result_file")"

  printf '\n================================================================\n'
  printf 'Claude Code will read and edit files inside ~/JayhilBridge/claude-code-jobs only because it starts there — it is still an AI agent; Robert reviews results before anything ships.\n'
  printf '================================================================\n\n'

  {
    printf '# Claude Code run — %s\n\n' "$(date '+%Y-%m-%d %H:%M %Z')"
    printf -- '- Job source: %s\n' "$source_label"
    printf -- '- Work folder: %s\n' "$WORKDIR"
    printf -- '- Permission mode: %s (max turns %s, output: text)\n' "$PERMISSION_MODE" "$MAX_TURNS"
    printf -- '- Transcript: %s\n\n' "$result_name"
    printf -- '---\n\n'
  } > "$result_file"

  local old_pwd="$PWD"
  cd "$WORKDIR" || { printf 'Could not enter the work folder: %s\n' "$WORKDIR"; return 1; }
  "$CLAUDE_BIN" -p "$prompt" --output-format text \
    --permission-mode "$PERMISSION_MODE" --max-turns "$MAX_TURNS" 2>&1 \
    | tee -a "$result_file"
  rc=${PIPESTATUS[0]}
  cd "$old_pwd" || true

  finish_time="$(date '+%Y-%m-%d %H:%M %Z')"
  {
    printf '\n---\n\n'
    printf 'Exit code: %s\n' "$rc"
    printf 'Finished: %s\n' "$finish_time"
    printf 'Result file: %s\n' "$result_name"
  } >> "$result_file"

  if [ -n "$queue_note" ]; then
    mv "$queue_note" "$ARCHIVE_DIR/" 2>/dev/null
    printf 'Source note archived: %s\n' "$(basename "$queue_note")" >> "$result_file"
    printf '\nQueue note moved to messages/archive/.\n'
  fi

  printf '\nDone. Exit code %s. Full transcript: %s\n' "$rc" "$result_file"
  return $rc
}

# ---------------------------------------------------------------------------
# Job sources, in priority order
# ---------------------------------------------------------------------------
run_with_file() {
  # $1 = prompt file path
  if [ -z "$1" ] || [ ! -f "$1" ]; then
    printf 'No such prompt file: %s\n' "$1"
    return 1
  fi
  local prompt
  prompt="$(prompt_from_file "$1")"
  do_run "$prompt" "file: $1" ""
}

run_with_text() {
  do_run "$1" "typed argument (--text)" ""
}

run_oldest_queued() {
  local note prompt
  note="$(oldest_queued_note)"
  if [ -z "$note" ]; then
    printf 'The queue is empty: no *.md notes in %s\n' "$QUEUE_DIR"
    return 1
  fi
  prompt="$(prompt_from_file "$note")"
  do_run "$prompt" "queued note: $(basename "$note")" "$note"
}

# ---------------------------------------------------------------------------
# Menu (double-click, no arguments)
# ---------------------------------------------------------------------------
show_menu() {
  while true; do
    cat <<'MENU'

================================================================
  RUN CLAUDE CODE — Jayhil Bridge
  Claude Code works inside ~/JayhilBridge/claude-code-jobs only.
================================================================

  1) Run the oldest queued note (messages/to-claude-code/)
  2) Type a job now
  3) Preflight only (check install, sign-in, folders)
  0) Quit

MENU
    printf 'Type a number and press Enter: '
    local choice
    read -r choice
    case "$choice" in
      1)
        if run_preflight; then
          run_oldest_queued
        fi
        ;;
      2)
        if run_preflight; then
          local typed
          typed="$(read_typed_job)"
          do_run "$typed" "typed in the window" ""
        fi
        ;;
      3)
        run_preflight
        printf '\nPreflight done. Nothing was run.\n'
        ;;
      0|q|Q|"")
        echo "Bye."
        break
        ;;
      *)
        echo "Please type 1, 2, 3, or 0."
        ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# Entry point
#   no args        -> menu
#   --run <file>   -> prompt from a file
#   --text "job"   -> prompt from the argument
#   --preflight    -> checks only
# There is deliberately NO full-auto / skip-permissions flag.
# ---------------------------------------------------------------------------
main() {
  case "${1:-}" in
    "")
      show_menu
      ;;
    --run)
      if run_preflight; then
        run_with_file "${2:-}"
      fi
      ;;
    --text)
      if run_preflight; then
        run_with_text "${2:-}"
      fi
      ;;
    --preflight)
      run_preflight
      ;;
    --full-auto)
      printf 'There is no full-auto mode. This launcher always runs with\n'
      printf 'permission mode "%s", a %s-turn cap, inside %s only.\n' "$PERMISSION_MODE" "$MAX_TURNS" "$WORKDIR"
      return 2
      ;;
    *)
      printf 'Unknown option: %s\n\n' "$1"
      printf 'Usage:\n'
      printf '  %s                 menu\n' "$0"
      printf '  %s --run <file>    run a job from a prompt file\n' "$0"
      printf '  %s --text "job"    run a job given as text\n' "$0"
      printf '  %s --preflight     checks only\n' "$0"
      return 2
      ;;
  esac
}

main "$@"
