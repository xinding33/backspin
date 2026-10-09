#!/bin/sh
# Installs Backspin to ~/Applications and starts it now and at every login
# (the "Start at Login" menu option). It relaunches if it crashes, but stays quit
# if you choose Quit from its menu.
set -eu
cd "$(dirname "$0")"
[ -d dist/Backspin.app ] || ./build.sh

LABEL=io.github.xinding33.backspin
APP="$HOME/Applications/Backspin.app"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents"
rm -rf "$APP"
cp -R dist/Backspin.app "$APP"

# Backspin was called ScrollFlip before 1.3.0. Backspin quits it and takes over its settings
# when it starts; remove the old app here. Reset its permission first: tccutil needs the app.
OLD_LABEL=io.github.xinding33.scrollflip
if [ -d "$HOME/Applications/ScrollFlip.app" ]; then
    launchctl bootout "$DOMAIN/$OLD_LABEL" 2>/dev/null || true
    tccutil reset Accessibility "$OLD_LABEL" >/dev/null 2>&1 || true
    rm -rf "$HOME/Applications/ScrollFlip.app"
fi

"$APP/Contents/MacOS/Backspin" --install-launch-agent
launchctl bootstrap "$DOMAIN" "$PLIST"
echo "Backspin installed and running. Grant it Accessibility access if prompted."
echo "Log: ~/Library/Logs/Backspin.log"
