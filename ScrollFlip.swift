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

let home = FileManager.default.homeDirectoryForCurrentUser
let logURL = home.appendingPathComponent("Library/Logs/ScrollFlip.log")
let agentLabel = "io.github.xinding33.scrollflip"
let agentURL = home.appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")
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

/// The executable path launchd should run. For Homebrew installs, use the
/// version-independent opt/ path so it keeps working after upgrades.
func stableExecutablePath() -> String {
    Bundle.main.executablePath!.replacingOccurrences(
        of: #"/Cellar/scrollflip/[^/]+/"#, with: "/opt/scrollflip/", options: .regularExpression)
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
        menu.addItem(item("Start at Login", #selector(toggleStartAtLogin), checked: startsAtLogin))
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
