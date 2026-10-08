#!/bin/sh
# Installs ScrollFlip to ~/Applications and starts it now and at every login
# (the "Start at Login" menu option). It relaunches if it crashes, but stays quit
# if you choose Quit from its menu.
set -eu
cd "$(dirname "$0")"
[ -d build/ScrollFlip.app ] || ./build.sh

LABEL=io.github.xinding33.scrollflip
APP="$HOME/Applications/ScrollFlip.app"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents"
rm -rf "$APP"
cp -R build/ScrollFlip.app "$APP"

"$APP/Contents/MacOS/ScrollFlip" --install-launch-agent
launchctl bootstrap "$DOMAIN" "$PLIST"
echo "ScrollFlip installed and running. Grant it Accessibility access if prompted."
echo "Log: ~/Library/Logs/ScrollFlip.log"
