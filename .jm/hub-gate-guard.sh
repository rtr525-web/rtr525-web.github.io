#!/bin/bash
# Re-locks the Empire Hub if a sync publishes it without the PIN gate.
# Restores empire/index.html from the newest commit where it was still gated.
F=empire/index.html
[ -f "$F" ] || exit 0
grep -q 'PIN required' "$F" && { echo "hub lock OK"; exit 0; }
for c in $(git log --format=%H -n 200 -- "$F"); do
  if git show "$c:$F" 2>/dev/null | grep -q 'PIN required'; then
    git show "$c:$F" > "$F"; echo "hub lock restored from $c"; exit 0
  fi
done
echo "::error::Empire Hub is unlocked and no gated version was found in history"; exit 1
