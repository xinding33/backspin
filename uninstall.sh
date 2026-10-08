#!/bin/sh
# Stops ScrollFlip and removes it. Also remove its Accessibility entry in System Settings.
set -eu
LABEL=io.github.xinding33.scrollflip
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
rm -rf "$HOME/Applications/ScrollFlip.app"
tccutil reset Accessibility "$LABEL" >/dev/null 2>&1 || true
echo "ScrollFlip removed."
