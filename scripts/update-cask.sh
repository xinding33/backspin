#!/bin/bash
# Writes the backspin cask for a release into a homebrew-tap checkout, and retires the
# scrollflip formula (Backspin's name and source build before 1.3.0).
# Usage: scripts/update-cask.sh TAP_DIR VERSION SHA256
#
# Backspin updates itself from 1.4.0, but the cask doesn't say `auto_updates true` yet: brew upgrade
# would then skip Backspin, stranding 1.3.0, which can't update itself. Add it in a later release.
set -euo pipefail
TAP="$1" VERSION="$2" SHA="$3"
mkdir -p "$TAP/Casks"
cat > "$TAP/Casks/backspin.rb" <<CASK
cask "backspin" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/xinding33/backspin/releases/download/v#{version}/Backspin-#{version}.zip"
  name "Backspin"
  desc "Menu bar app that reverses mouse wheel scrolling but keeps the trackpad natural"
  homepage "https://github.com/xinding33/backspin"

  depends_on macos: :ventura

  app "Backspin.app"

  # brew upgrade reopens it afterwards.
  uninstall quit: "io.github.xinding33.backspin"

  zap trash: [
    "~/Library/LaunchAgents/io.github.xinding33.backspin.plist",
    "~/Library/LaunchAgents/io.github.xinding33.scrollflip.plist",
    "~/Library/Logs/Backspin.log",
    "~/Library/Logs/ScrollFlip.log",
    "~/Library/Preferences/io.github.xinding33.backspin.plist",
    "~/Library/Preferences/io.github.xinding33.scrollflip.plist",
  ]
end
CASK
rm -f "$TAP/Formula/scrollflip.rb"
# brew update moves scrollflip formula installs to the cask (or says how, if the cask isn't trusted yet).
MIGRATIONS="$TAP/tap_migrations.json"
[ -f "$MIGRATIONS" ] || echo '{}' > "$MIGRATIONS"
jq '.scrollflip = "backspin"' "$MIGRATIONS" > "$MIGRATIONS.new"
mv "$MIGRATIONS.new" "$MIGRATIONS"
