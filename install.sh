#!/bin/sh
# Installs ScrollFlip to ~/Applications and starts it now and at every login.
# It relaunches if it crashes, but stays quit if you choose Quit from its menu.
set -eu
cd "$(dirname "$0")"
[ -d build/ScrollFlip.app ] || ./build.sh

LABEL=local.scrollflip
APP="$HOME/Applications/ScrollFlip.app"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
rm -rf "$APP"
cp -R build/ScrollFlip.app "$APP"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$APP/Contents/MacOS/ScrollFlip</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/ScrollFlip.log</string>
</dict>
</plist>
PLIST

launchctl bootstrap "$DOMAIN" "$PLIST"
echo "ScrollFlip installed and running. Grant it Accessibility access if prompted."
echo "Log: ~/Library/Logs/ScrollFlip.log"
