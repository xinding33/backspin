#!/bin/sh
# Stops Backspin and removes it. Also remove its Accessibility entry in System Settings.
set -eu
LABEL=io.github.xinding33.backspin
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
# Reset permission before deleting the app: tccutil needs the app to resolve its bundle ID.
tccutil reset Accessibility "$LABEL" >/dev/null 2>&1 || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
rm -rf "$HOME/Applications/Backspin.app"
echo "Backspin removed."
