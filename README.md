# ScrollFlip

A tiny macOS menu bar app that reverses mouse-wheel scrolling while leaving trackpad scrolling alone.

macOS has a single "Natural scrolling" setting shared by every mouse and trackpad. With ScrollFlip running and Natural scrolling **on**, the trackpad scrolls naturally and mouse wheels scroll the traditional way.

Unlike device-level remappers such as Karabiner-Elements, ScrollFlip works on scroll events rather than physical devices, so it also applies to a mouse used through Universal Control from another Mac.

## How it works

Trackpads (and Magic Mouse) send *continuous* scroll events; notched mouse wheels send *discrete* ones. ScrollFlip installs an event tap and negates both scroll axes on discrete events only. It's a single Swift file with no dependencies.

Known limitation: mice that emit continuous scroll events (e.g. Logitech mice with smooth scrolling enabled in Logi Options+) are treated like trackpads and aren't reversed.

## Install

Requires macOS 13+ and the Xcode command line tools.

```sh
./install.sh
```

This builds a universal app, copies it to `~/Applications/ScrollFlip.app`, and registers a LaunchAgent so it starts at login (and relaunches if it crashes). Grant it Accessibility access when prompted (System Settings → Privacy & Security → Accessibility); it starts working as soon as you do.

`build.sh` signs with your Apple Development certificate if you have one, so the Accessibility permission survives rebuilds. Otherwise it signs ad-hoc and you'll need to re-grant permission after each rebuild.

## Menu

- **Reverse Mouse Wheel**: pause or resume reversing (remembered across restarts)
- **Log Scroll Events**: log every scroll event to `~/Library/Logs/ScrollFlip.log`, with whether it was flipped
- **Show Log**, **Restart**, **Quit** (stays quit until next login)

## Uninstall

```sh
./uninstall.sh
```

Stops the app, removes the LaunchAgent and app, and resets its Accessibility permission.
