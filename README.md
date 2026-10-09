# Backspin

A tiny macOS menu bar app that reverses mouse-wheel scrolling while leaving trackpad scrolling alone.

macOS has a single "Natural scrolling" setting shared by every mouse and trackpad. With Backspin running and Natural scrolling **on**, the trackpad scrolls naturally and mouse wheels scroll the traditional way.

Unlike device-level remappers such as Karabiner-Elements, Backspin works on scroll events rather than physical devices, so it also applies to a mouse used through Universal Control from another Mac.

Backspin was called ScrollFlip before version 1.3.0.

## How it works

Trackpads (and Magic Mouse) send *continuous* scroll events; notched mouse wheels send *discrete* ones. Backspin installs an event tap and negates both scroll axes on discrete events only. It has no dependencies.

Known limitation: mice that emit continuous scroll events (e.g. Logitech mice with smooth scrolling enabled in Logi Options+) are treated like trackpads and aren't reversed.

## Install

Requires macOS 13+. Releases are universal (Apple silicon and Intel), signed with a Developer ID and notarized by Apple.

```sh
brew install --cask xinding33/tap/backspin
```

Or download `Backspin-x.y.z.zip` from the [latest release](https://github.com/xinding33/backspin/releases/latest), unzip it, and move `Backspin.app` to Applications.

Open Backspin and grant it Accessibility access when prompted (System Settings → Privacy & Security → Accessibility), and keep Natural scrolling on. It starts working as soon as permission is granted. Then choose **Start at Login** from its menu bar icon.

The permission carries over to later versions, so you grant it once. `brew upgrade` quits Backspin and reopens it afterwards.

### Upgrading from ScrollFlip

Install Backspin as above, then open it. Backspin quits ScrollFlip and takes over its settings and **Start at Login**. Because it's a new app to macOS, grant Accessibility access once more. This is the last time: ScrollFlip's builds weren't signed, so each upgrade needed it again, but signed Backspin releases keep the permission.

If you installed ScrollFlip with Homebrew, `brew update` installs the `backspin` cask in its place, or prints the commands to run if you haven't trusted the cask yet. To switch yourself, open Backspin before removing ScrollFlip, so Backspin can also clear ScrollFlip's Accessibility entry:

```sh
brew install --cask xinding33/tap/backspin
open -a Backspin
brew uninstall scrollflip
```

## Menu

- **Reverse Mouse Wheel**: pause or resume reversing
  - **Vertical**, **Horizontal**: choose which directions to reverse (both by default)
- **Start at Login**: start Backspin when you log in, and relaunch it if it crashes
- **Hide Menu Bar Icon**: Backspin keeps running without an icon. Open Backspin again to bring the icon back.
- **Log Scroll Events**: log every scroll event to `~/Library/Logs/Backspin.log`, with whether it was flipped
- **Show Log**, **Restart**, **Quit** (stays quit until you next log in or open it)

Settings are remembered across restarts.

To check permission and setup without changing anything:

```sh
/Applications/Backspin.app/Contents/MacOS/Backspin --diagnose
```

## Uninstall

Turn off **Start at Login** and quit Backspin from its menu, then:

```sh
tccutil reset Accessibility io.github.xinding33.backspin
brew uninstall --cask backspin
```

Or delete `Backspin.app` instead of the `brew uninstall`. Use `brew uninstall --zap --cask backspin` to also delete its settings and log.

## Build

Requires the Xcode command line tools.

```sh
git clone https://github.com/xinding33/backspin.git
cd backspin
./install.sh
```

This builds a universal app, copies it to `~/Applications/Backspin.app`, and starts it with **Start at Login** turned on. `build.sh` signs with your Apple Development certificate if you have one, so the Accessibility permission survives rebuilds; otherwise it signs ad-hoc and you'll need to re-grant permission after each rebuild. `./uninstall.sh` stops the app, turns off Start at Login, resets its Accessibility permission, and deletes the app.

Run the tests with `swift test` (requires Xcode).

### Release

Pushing a `v*` tag runs `.github/workflows/release.yml`, which tests, signs with the hardened runtime, notarizes and staples the app, publishes `Backspin-x.y.z.zip` to a GitHub Release, and updates the cask in [xinding33/homebrew-tap](https://github.com/xinding33/homebrew-tap). It needs these secrets in a `release` environment restricted to `v*` tags: `DEVELOPER_ID_P12` and `DEVELOPER_ID_P12_PASSWORD` (the base64-encoded Developer ID Application certificate and its password), `NOTARY_KEY`, `NOTARY_KEY_ID` and `NOTARY_ISSUER_ID` (a base64-encoded App Store Connect API key), and `TAP_DEPLOY_KEY` (a deploy key with write access to the tap).

To produce the same notarized ZIP locally, save notary credentials once with `xcrun notarytool store-credentials backspin-notary` (or set `NOTARY_PROFILE` to an existing profile), then run `scripts/release.sh`.

## AI disclosure

Backspin's implementation and documentation were developed with AI assistance.

## License

Copyright 2026 Xin Ding. Licensed under the [Apache License, Version 2.0](LICENSE).
