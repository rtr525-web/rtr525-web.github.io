#!/bin/bash
# InstallMuseConnection.command
#
# Puts the "Muse Connection" live status into your Mac's menu bar,
# up by the Wi-Fi and battery icons.
#
# It uses a free, well-known app called SwiftBar that hosts little
# status scripts like ours. This installer NEVER downloads or installs
# anything by itself: if SwiftBar isn't on your Mac yet, it opens the
# official download page, tells you the three clicks, and stops — you
# run this installer again afterwards and it finishes the job.
#
# Safe to run more than once. It copies one small script file and
# that's all it changes on your Mac.

set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_SRC="$DIR/muse-connection.15s.sh"
PLUGIN_NAME="muse-connection.15s.sh"
PLUGINS_DIR="$HOME/Library/Application Support/SwiftBar/Plugins"
RELEASES_URL="https://github.com/swiftbar/SwiftBar/releases"

echo "Muse Connection — menu bar installer"
echo "======================================"
echo

# The plugin file has to be sitting next to this installer.
if [ ! -f "$PLUGIN_SRC" ]; then
  echo "PROBLEM: I can't find the status script:"
  echo "  $PLUGIN_SRC"
  echo "Keep InstallMuseConnection.command and muse-connection.15s.sh"
  echo "in the same folder and try again."
  echo
  read -r -p "Press Enter to close this window. " _
  exit 1
fi

# Step 1 — is SwiftBar installed?
swiftbar_found=0
if [ -d "/Applications/SwiftBar.app" ] || [ -d "$HOME/Applications/SwiftBar.app" ]; then
  swiftbar_found=1
fi

if [ "$swiftbar_found" -eq 0 ]; then
  echo "One thing is needed first: SwiftBar, the free app that hosts"
  echo "menu-bar status scripts. It is not on this Mac yet."
  echo
  echo "I'm opening its official download page in your browser now."
  echo "On that page:"
  echo "  1) Download the latest SwiftBar (the .dmg file)."
  echo "  2) Open the .dmg and drag SwiftBar into Applications."
  echo "  3) Open SwiftBar once from Applications"
  echo "     (if macOS asks, confirm Open — it's a known open-source app)."
  echo "  4) Come back and double-click this installer again."
  echo
  echo "Nothing else to do — the installer does the rest next time."
  open "$RELEASES_URL" 2>/dev/null || echo "Open this page yourself: $RELEASES_URL"
  echo
  read -r -p "Press Enter to close this window. " _
  exit 0
fi

echo "SwiftBar found. Installing the Muse Connection status script..."

# Step 2 — SwiftBar's plugins folder (the standard location).
mkdir -p "$PLUGINS_DIR"
cp "$PLUGIN_SRC" "$PLUGINS_DIR/$PLUGIN_NAME"
chmod +x "$PLUGINS_DIR/$PLUGIN_NAME"

# Step 3 — ask SwiftBar to pick it up right away.
open "swiftbar://refreshallplugins" 2>/dev/null || true

echo
echo "DONE."
echo
echo "Look at the top-right of your screen, by the Wi-Fi and battery"
echo "icons. Within about 15 seconds you should see:"
echo
echo "    Muse ●"
echo
echo "The dot is green when the Bridge is running, yellow while it is"
echo "working on a job, and red when the Bridge is off. Click it for"
echo "details and one-click actions (Start the Bridge, Self-Test, and"
echo "the Bridge folder)."
echo
echo "One possible hiccup: if SwiftBar asks you to choose a plugins"
echo "folder, choose this one:"
echo "  $PLUGINS_DIR"
echo
read -r -p "Press Enter to close this window. " _
exit 0
