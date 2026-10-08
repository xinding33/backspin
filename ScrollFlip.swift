// ScrollFlip: reverses mouse-wheel scrolling while leaving trackpad scrolling alone.
//
// Trackpads (and Magic Mouse) send "continuous" scroll events; notched mouse wheels
// send discrete ones. We flip only the discrete events, so with system "Natural
// scrolling" on, the trackpad stays natural and the mouse wheel becomes traditional.
// Works on any scroll event that reaches the window server, including ones injected
// by Universal Control.

import AppKit
import ApplicationServices

let defaults = UserDefaults.standard
var enabled = defaults.object(forKey: "enabled") as? Bool ?? true
var reverseVertical = defaults.object(forKey: "reverseVertical") as? Bool ?? true
var reverseHorizontal = defaults.object(forKey: "reverseHorizontal") as? Bool ?? true
var iconHidden = defaults.bool(forKey: "iconHidden")
var verbose = CommandLine.arguments.contains("--log")
var tap: CFMachPort?

let home = FileManager.default.homeDirectoryForCurrentUser
let logURL = home.appendingPathComponent("Library/Logs/ScrollFlip.log")
let agentLabel = "io.github.xinding33.scrollflip"
let agentURL = home.appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")
let showIconNotification = Notification.Name("\(agentLabel).showIcon")
let accessibilitySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

let logFile: FileHandle? = {
    if !FileManager.default.fileExists(atPath: logURL.path) {
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
    }
    let handle = try? FileHandle(forWritingTo: logURL)
    handle?.seekToEndOfFile()
    return handle
}()
let timestamp = ISO8601DateFormatter()

/// Appends to ~/Library/Logs/ScrollFlip.log, and echoes to the terminal when run from one.
func log(_ message: String) {
    let line = "\(timestamp.string(from: Date())) \(message)\n".data(using: .utf8)!
    logFile?.write(line)
    if isatty(STDERR_FILENO) != 0 { FileHandle.standardError.write(line) }
}

/// Negates the vertical (axis 1) and/or horizontal (axis 2) scroll deltas.
func flip(_ event: CGEvent, vertical: Bool, horizontal: Bool) {
    // Read everything first: setting the line delta makes the system recompute the others.
    let line1 = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
    let line2 = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
    let fixed1 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
    let fixed2 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
    let point1 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
    let point2 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
    let sign1: Int64 = vertical ? -1 : 1
    let sign2: Int64 = horizontal ? -1 : 1

    event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: sign1 * line1)
    event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: sign2 * line2)
    event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Double(sign1) * fixed1)
    event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: Double(sign2) * fixed2)
    event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: sign1 * point1)
    event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: sign2 * point2)
}

let callback: CGEventTapCallBack = { _, type, event, _ in
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    case .scrollWheel:
        let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let flipping = enabled && !continuous && (reverseVertical || reverseHorizontal)
        if verbose {
            let pid = event.getIntegerValueField(.eventSourceUnixProcessID)
            let dy = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            let dx = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
            log("scroll continuous=\(continuous) dy=\(dy) dx=\(dx) sourcePID=\(pid) -> \(flipping ? "flip" : "pass")")
        }
        if flipping { flip(event, vertical: reverseVertical, horizontal: reverseHorizontal) }
    default:
        break
    }
    return Unmanaged.passUnretained(event)
}

/// The app's path for launchd and the user. For Homebrew installs, use the
/// version-independent opt/ path so it keeps working after upgrades.
func stableBundlePath() -> String {
    Bundle.main.bundlePath.replacingOccurrences(
        of: #"/Cellar/scrollflip/[^/]+/"#, with: "/opt/scrollflip/", options: .regularExpression)
}

func stableExecutablePath() -> String {
    stableBundlePath() + "/Contents/MacOS/ScrollFlip"
}

/// Start at login is a LaunchAgent, which also relaunches ScrollFlip if it crashes.
var startsAtLogin: Bool { FileManager.default.fileExists(atPath: agentURL.path) }

func writeLaunchAgent() throws {
    let plist: [String: Any] = [
        "Label": agentLabel,
        "ProgramArguments": [stableExecutablePath()],
        "RunAtLoad": true,
        "KeepAlive": ["SuccessfulExit": false],
        "ProcessType": "Interactive",
    ]
    try FileManager.default.createDirectory(at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: agentURL)
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

        // Started by our login item: honor Hide Menu Bar Icon. Opened by the user: show it.
        let startedAtLogin = ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] == agentLabel
        if !startedAtLogin { setIconHidden(false) }
        DistributedNotificationCenter.default().addObserver(
            forName: showIconNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.setIconHidden(false) }

        if !startTap() {
            // Any existing Accessibility entry is for an older build (each unsigned build looks
            // like a new app to macOS), and it blocks the prompt. Clear it so the prompt shows.
            let reset = Process()
            reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            reset.arguments = ["reset", "Accessibility", agentLabel]
            try? reset.run()
            reset.waitUntilExit()

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

    /// Opening ScrollFlip while it's running shows the icon again.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        setIconHidden(false)
        return false
    }

    func updateIcon() {
        statusItem.button?.appearsDisabled = !enabled || tap == nil
        // Never hide the icon while it's the only way to see that permission is missing.
        statusItem.isVisible = !iconHidden || tap == nil
    }

    func setIconHidden(_ hidden: Bool) {
        iconHidden = hidden
        defaults.set(hidden, forKey: "iconHidden")
        updateIcon()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.autoenablesItems = false

        if tap == nil {
            menu.addItem(label("Waiting for Accessibility permission"))
            menu.addItem(item("Open Accessibility Settings…", #selector(openAccessibilitySettings)))
        } else {
            let status = enabled ? "Reversing mouse wheel" : "Paused"
            menu.addItem(label("ScrollFlip: \(status)"))
        }
        menu.addItem(.separator())
        menu.addItem(item("Reverse Mouse Wheel", #selector(toggleEnabled), checked: enabled))
        for (title, action, checked) in [
            ("Vertical", #selector(toggleVertical), reverseVertical),
            ("Horizontal", #selector(toggleHorizontal), reverseHorizontal),
        ] {
            let axis = item(title, action, checked: checked)
            axis.indentationLevel = 1
            axis.isEnabled = enabled
            menu.addItem(axis)
        }
        menu.addItem(.separator())
        menu.addItem(item("Start at Login", #selector(toggleStartAtLogin), checked: startsAtLogin))
        menu.addItem(item("Hide Menu Bar Icon…", #selector(hideIcon)))
        menu.addItem(.separator())
        menu.addItem(item("Log Scroll Events", #selector(toggleLogging), checked: verbose))
        menu.addItem(item("Show Log", #selector(showLog)))
        menu.addItem(.separator())
        menu.addItem(item("Restart", #selector(restart)))
        menu.addItem(item("Quit ScrollFlip", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
    }

    private func label(_ title: String) -> NSMenuItem {
        let label = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        label.isEnabled = false
        return label
    }

    private func item(_ title: String, _ action: Selector, checked: Bool = false, key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? self
        item.state = checked ? .on : .off
        return item
    }

    @objc func toggleEnabled() {
        enabled.toggle()
        defaults.set(enabled, forKey: "enabled")
        log("Reversing \(enabled ? "on" : "off")")
        updateIcon()
    }

    @objc func toggleVertical() {
        reverseVertical.toggle()
        defaults.set(reverseVertical, forKey: "reverseVertical")
        log("Reverse vertical \(reverseVertical ? "on" : "off")")
    }

    @objc func toggleHorizontal() {
        reverseHorizontal.toggle()
        defaults.set(reverseHorizontal, forKey: "reverseHorizontal")
        log("Reverse horizontal \(reverseHorizontal ? "on" : "off")")
    }

    @objc func hideIcon() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Hide the ScrollFlip menu bar icon?"
        alert.informativeText = """
            ScrollFlip keeps running. To show the icon again, open ScrollFlip again:

            open "\(stableBundlePath())"
            """
        alert.addButton(withTitle: "Hide Icon")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            setIconHidden(true)
        }
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

    @objc func toggleStartAtLogin() {
        do {
            if startsAtLogin {
                try FileManager.default.removeItem(at: agentURL)
            } else {
                try writeLaunchAgent()
            }
            log("Start at login \(startsAtLogin ? "on" : "off")")
        } catch {
            log("Couldn't change start at login: \(error)")
        }
    }

    @objc func restart() {
        log("Restarting")
        var args = CommandLine.arguments.map { strdup($0) } + [nil]
        execv(stableExecutablePath(), &args)
    }
}

if CommandLine.arguments.contains("--install-launch-agent") {
    // Used by install.sh to turn on Start at Login without launching the app.
    try writeLaunchAgent()
    exit(0)
}

// Only one copy may run, or the wheel would be flipped twice. O_CLOEXEC releases
// the lock when Restart execs a fresh copy.
let lockFD = open(NSTemporaryDirectory() + "\(agentLabel).lock", O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
if flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
    // Opening ScrollFlip again is how you bring back a hidden icon.
    DistributedNotificationCenter.default().postNotificationName(
        showIconNotification, object: nil, userInfo: nil, deliverImmediately: true)
    log("Another copy of ScrollFlip is already running")
    exit(0)
}

// Keep the login item pointing at this copy if the app has moved.
if startsAtLogin { try? writeLaunchAgent() }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
