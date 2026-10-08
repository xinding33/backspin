// ScrollFlip: reverses mouse-wheel scrolling while leaving trackpad scrolling alone.
//
// Trackpads (and Magic Mouse) send "continuous" scroll events; notched mouse wheels
// send discrete ones. We flip only the discrete events, so with system "Natural
// scrolling" on, the trackpad stays natural and the mouse wheel becomes traditional.
// Works on any scroll event that reaches the window server, including ones injected
// by Universal Control.

import AppKit
import ApplicationServices

let enabledKey = "enabled"
var enabled = UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
var verbose = CommandLine.arguments.contains("--log")
var tap: CFMachPort?

let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/ScrollFlip.log")
let accessibilitySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

func log(_ message: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    FileHandle.standardError.write("\(stamp) \(message)\n".data(using: .utf8)!)
}

func flip(_ event: CGEvent) {
    // Read everything first: setting the line delta makes the system recompute the others.
    let line1 = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
    let line2 = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
    let fixed1 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
    let fixed2 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
    let point1 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
    let point2 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)

    event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -line1)
    event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: -line2)
    event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -fixed1)
    event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -fixed2)
    event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: -point1)
    event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: -point2)
}

let callback: CGEventTapCallBack = { _, type, event, _ in
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    case .scrollWheel:
        let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let flipping = enabled && !continuous
        if verbose {
            let pid = event.getIntegerValueField(.eventSourceUnixProcessID)
            let dy = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            let dx = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
            log("scroll continuous=\(continuous) dy=\(dy) dx=\(dx) sourcePID=\(pid) -> \(flipping ? "flip" : "pass")")
        }
        if flipping { flip(event) }
    default:
        break
    }
    return Unmanaged.passUnretained(event)
}

/// Creates the event tap. Fails until the app has Accessibility permission.
func startTap() -> Bool {
    if tap != nil { return true }
    let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
    guard let newTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
        eventsOfInterest: mask, callback: callback, userInfo: nil
    ) else { return false }
    tap = newTap
    CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, newTap, 0), .commonModes)
    CGEvent.tapEnable(tap: newTap, enable: true)
    log("ScrollFlip running")
    return true
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem.button?.image = NSImage(systemSymbolName: "computermouse", accessibilityDescription: "ScrollFlip")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        if !startTap() {
            // Prompt once, then keep retrying; the tap succeeds as soon as permission is granted.
            AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            log("Waiting for Accessibility permission (System Settings > Privacy & Security > Accessibility)")
            Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
                if startTap() {
                    timer.invalidate()
                    self?.updateIcon()
                }
            }
        }
        updateIcon()
    }

    func updateIcon() {
        statusItem.button?.appearsDisabled = !enabled || tap == nil
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if tap == nil {
            menu.addItem(NSMenuItem(title: "Waiting for Accessibility permission", action: nil, keyEquivalent: ""))
            menu.addItem(item("Open Accessibility Settings…", #selector(openAccessibilitySettings)))
        } else {
            let status = enabled ? "Reversing mouse wheel" : "Paused"
            menu.addItem(NSMenuItem(title: "ScrollFlip: \(status)", action: nil, keyEquivalent: ""))
        }
        menu.addItem(.separator())
        menu.addItem(item("Reverse Mouse Wheel", #selector(toggleEnabled), checked: enabled))
        menu.addItem(item("Log Scroll Events", #selector(toggleLogging), checked: verbose))
        menu.addItem(item("Show Log", #selector(showLog)))
        menu.addItem(.separator())
        menu.addItem(item("Restart", #selector(restart)))
        menu.addItem(item("Quit ScrollFlip", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
    }

    private func item(_ title: String, _ action: Selector, checked: Bool = false, key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? self
        item.state = checked ? .on : .off
        return item
    }

    @objc func toggleEnabled() {
        enabled.toggle()
        UserDefaults.standard.set(enabled, forKey: enabledKey)
        log("Reversing \(enabled ? "on" : "off")")
        updateIcon()
    }

    @objc func toggleLogging() {
        verbose.toggle()
        log("Per-event logging \(verbose ? "on" : "off")")
    }

    @objc func showLog() {
        NSWorkspace.shared.open(logURL)
    }

    @objc func openAccessibilitySettings() {
        NSWorkspace.shared.open(accessibilitySettingsURL)
    }

    @objc func restart() {
        log("Restarting")
        let path = Bundle.main.executablePath!
        var args = CommandLine.arguments.map { strdup($0) } + [nil]
        execv(path, &args)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
