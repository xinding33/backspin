# ScrollFlip

A tiny macOS menu bar app that reverses mouse-wheel scrolling while leaving trackpad scrolling alone.

macOS has a single "Natural scrolling" setting shared by every mouse and trackpad. With ScrollFlip running and Natural scrolling **on**, the trackpad scrolls naturally and mouse wheels scroll the traditional way.

Unlike device-level remappers such as Karabiner-Elements, ScrollFlip works on scroll events rather than physical devices, so it also applies to a mouse used through Universal Control from another Mac.

## How it works

Trackpads (and Magic Mouse) send *continuous* scroll events; notched mouse wheels send *discrete* ones. ScrollFlip installs an event tap and negates both scroll axes on discrete events only. It's a single Swift file with no dependencies.

Known limitation: mice that emit continuous scroll events (e.g. Logitech mice with smooth scrolling enabled in Logi Options+) are treated like trackpads and aren't reversed.

## Install

Requires macOS 13+. Both methods build ScrollFlip on your Mac, so there's no Gatekeeper warning. (Signed and notarized downloads are planned; see [#1](https://github.com/xinding33/scrollflip/issues/1).)

### Homebrew

```sh
brew install xinding33/tap/scrollflip
open "$(brew --prefix)/opt/scrollflip/ScrollFlip.app"
```

Grant ScrollFlip Accessibility access when prompted (System Settings → Privacy & Security → Accessibility), and keep Natural scrolling on. It starts working as soon as permission is granted. Then choose **Start at Login** from its menu bar icon.

Because these builds aren't signed with a Developer ID, macOS treats each upgrade as a new app. After `brew upgrade scrollflip`, choose **Restart** from ScrollFlip's menu and grant Accessibility access again when prompted.

### From source

Requires the Xcode command line tools.

```sh
git clone https://github.com/xinding33/scrollflip.git
cd scrollflip
./install.sh
```

This builds a universal app, copies it to `~/Applications/ScrollFlip.app`, and starts it with **Start at Login** turned on. `build.sh` signs with your Apple Development certificate if you have one, so the Accessibility permission survives rebuilds; otherwise it signs ad-hoc and you'll need to re-grant permission after each rebuild.

## Menu

- **Reverse Mouse Wheel**: pause or resume reversing
  - **Vertical**, **Horizontal**: choose which directions to reverse (both by default)
- **Start at Login**: start ScrollFlip when you log in, and relaunch it if it crashes
- **Hide Menu Bar Icon**: ScrollFlip keeps running without an icon. Open ScrollFlip again to bring the icon back.
- **Log Scroll Events**: log every scroll event to `~/Library/Logs/ScrollFlip.log`, with whether it was flipped
- **Show Log**, **Restart**, **Quit** (stays quit until you next log in or open it)

Settings are remembered across restarts.

## Uninstall

Homebrew: turn off **Start at Login** and quit ScrollFlip from its menu, then:

```sh
tccutil reset Accessibility io.github.xinding33.scrollflip
brew uninstall scrollflip
```

From source:

```sh
./uninstall.sh
```

Stops the app, turns off Start at Login, resets its Accessibility permission, and deletes the app.

## AI disclosure

ScrollFlip's implementation and documentation were developed with AI assistance.

## License

Copyright 2026 Xin Ding. Licensed under the [Apache License, Version 2.0](LICENSE).
