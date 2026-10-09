// Backspin: reverses mouse-wheel scrolling while leaving trackpad scrolling alone.
//
// Trackpads (and Magic Mouse) send "continuous" scroll events; notched mouse wheels
// send discrete ones. We flip only the discrete events, so with system "Natural
// scrolling" on, the trackpad stays natural and the mouse wheel becomes traditional.
// Works on any scroll event that reaches the window server, including ones injected
// by Universal Control.

import AppKit
import ApplicationServices
import BackspinCore

let bundleID = "io.github.xinding33.backspin"
// Backspin was called ScrollFlip before 1.3.0.
let legacyBundleID = "io.github.xinding33.scrollflip"

let defaults = UserDefaults.standard
let home = FileManager.default.homeDirectoryForCurrentUser
let logURL = home.appendingPathComponent("Library/Logs/Backspin.log")
let legacyLogURL = home.appendingPathComponent("Library/Logs/ScrollFlip.log")
let agent = LaunchAgent(label: bundleID, directory: home.appendingPathComponent("Library/LaunchAgents"))
let legacyAgent = LaunchAgent(label: legacyBundleID, directory: home.appendingPathComponent("Library/LaunchAgents"))
let executablePath = Bundle.main.executablePath!
let showIconNotification = Notification.Name("\(bundleID).showIcon")
let accessibilitySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
let scrollMask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
let appVersion = Version(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") ?? Version("0.0.0")!
var autoUpdate = defaults.object(forKey: "autoUpdate") as? Bool ?? true

if CommandLine.arguments.contains("--diagnose") {
    // Read-only. The probe tap is removed before it's ever added to a run loop.
    let probe = CGEvent.tapCreate(
        tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
        eventsOfInterest: scrollMask, callback: { _, _, event, _ in Unmanaged.passUnretained(event) }, userInfo: nil)
    if let probe { CFMachPortInvalidate(probe) }
    let legacyRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: legacyBundleID).isEmpty
    print("""
        Backspin \(appVersion) at \(Bundle.main.bundlePath)
        Accessibility permission: \(AXIsProcessTrusted() ? "granted" : "not granted")
        Event tap: \(probe == nil ? "unavailable" : "available")
        Start at Login: \(agent.isInstalled ? "on" : "off")
        Install Updates Automatically: \(autoUpdate ? "on" : "off")\
        \(Updater.isDeveloperIDSigned(Bundle.main.bundleURL) ? "" : " (source build: can't update itself)")
        ScrollFlip: \(legacyRunning ? "running" : "not running"), \
        settings \(LegacyMigration.hasSettings(in: legacyBundleID, defaults) ? "present" : "absent"), \
        Start at Login \(legacyAgent.isInstalled ? "on" : "off")
        """)
    exit(0)
}

if CommandLine.arguments.contains("--install-launch-agent") {
    // Used by install.sh to turn on Start at Login without launching the app.
    try agent.install(executable: executablePath)
    exit(0)
}

LegacyMigration.moveLog(from: legacyLogURL, to: logURL)

// O_APPEND so a second copy's lines (e.g. "already running") don't get overwritten.
let logFile: FileHandle? = {
    let fd = open(logURL.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o644)
    return fd < 0 ? nil : FileHandle(fileDescriptor: fd, closeOnDealloc: true)
}()
let timestamp = ISO8601DateFormatter()

/// Appends to ~/Library/Logs/Backspin.log, and echoes to the terminal when run from one.
func log(_ message: String) {
    let line = "\(timestamp.string(from: Date())) \(message)\n".data(using: .utf8)!
    logFile?.write(line)
    if isatty(STDERR_FILENO) != 0 { FileHandle.standardError.write(line) }
}

/// Runs a command line tool and waits for it, discarding its output.
func run(_ path: String, _ arguments: String...) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
}

// Only one copy may run, or the wheel would be flipped twice. O_CLOEXEC releases
// the lock when Restart execs a fresh copy.
let lockFD = open(NSTemporaryDirectory() + "\(bundleID).lock", O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
if flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
    // Opening Backspin again is how you bring back a hidden icon.
    DistributedNotificationCenter.default().postNotificationName(
        showIconNotification, object: nil, userInfo: nil, deliverImmediately: true)
    log("Another copy of Backspin is already running")
    exit(0)
}

/// Quits a running ScrollFlip, which would flip the wheel back, and takes over its settings
/// and Start at Login. Does nothing once ScrollFlip is gone.
func migrateFromScrollFlip() {
    let pids = NSRunningApplication.runningApplications(withBundleIdentifier: legacyBundleID).map(\.processIdentifier)
    guard !pids.isEmpty || legacyAgent.isInstalled || LegacyMigration.hasSettings(in: legacyBundleID, defaults)
    else { return }
    log("Taking over from ScrollFlip")

    // Unload its login item first, or launchd would relaunch it.
    run("/bin/launchctl", "bootout", "gui/\(getuid())/\(legacyBundleID)")
    pids.forEach { kill($0, SIGTERM) }
    let deadline = Date().addingTimeInterval(5)
    while pids.contains(where: { kill($0, 0) == 0 }) && Date() < deadline { usleep(100_000) }
    pids.filter { kill($0, 0) == 0 }.forEach { kill($0, SIGKILL) }
    // Remove its entry from the Accessibility list.
    run("/usr/bin/tccutil", "reset", "Accessibility", legacyBundleID)

    LegacyMigration.moveSettings(from: legacyBundleID, to: defaults)
    do {
        try LegacyMigration.moveLaunchAgent(from: legacyAgent, to: agent, executable: executablePath)
    } catch {
        log("Couldn't move Start at Login over from ScrollFlip: \(error)")
    }
}

migrateFromScrollFlip()

var enabled = defaults.object(forKey: "enabled") as? Bool ?? true
var reverseVertical = defaults.object(forKey: "reverseVertical") as? Bool ?? true
var reverseHorizontal = defaults.object(forKey: "reverseHorizontal") as? Bool ?? true
var iconHidden = defaults.bool(forKey: "iconHidden")
var verbose = CommandLine.arguments.contains("--log")
var tap: CFMachPort?

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

var startsAtLogin: Bool { agent.isInstalled }

// Only release builds can install releases: an update must be signed the same way.
let canInstallUpdates = Updater.isDeveloperIDSigned(Bundle.main.bundleURL)

/// Creates the event tap. Fails until the app has Accessibility permission.
func startTap() -> Bool {
    if tap != nil { return true }
    guard let newTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
        eventsOfInterest: scrollMask, callback: callback, userInfo: nil
    ) else { return false }
    tap = newTap
    CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, newTap, 0), .commonModes)
    CGEvent.tapEnable(tap: newTap, enable: true)
    log("Backspin running")
    return true
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    /// What the updater is doing, or nil when it's idle.
    var updateStatus: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem.button?.image = NSImage(systemSymbolName: "computermouse", accessibilityDescription: "Backspin")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // Started by our login item: honor Hide Menu Bar Icon. Opened by the user: show it.
        let startedAtLogin = ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] == agent.label
        if !startedAtLogin { setIconHidden(false) }
        DistributedNotificationCenter.default().addObserver(
            forName: showIconNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.setIconHidden(false) }

        if !startTap() {
            // An existing Accessibility entry for a differently signed copy (such as an ad-hoc
            // source build) blocks the prompt. Clear it so the prompt shows.
            run("/usr/bin/tccutil", "reset", "Accessibility", bundleID)

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

        checkForUpdatesAutomatically()
        Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            self?.checkForUpdatesAutomatically()
        }
    }

    /// Opening Backspin while it's running shows the icon again.
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
            menu.addItem(label("Backspin: \(status)"))
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
        let check = item(updateStatus ?? "Check for Updates…", #selector(checkForUpdates))
        check.isEnabled = updateStatus == nil
        menu.addItem(check)
        let automatic = item("Install Updates Automatically", #selector(toggleAutoUpdate), checked: autoUpdate && canInstallUpdates)
        automatic.isEnabled = canInstallUpdates
        menu.addItem(automatic)
        menu.addItem(.separator())
        menu.addItem(item("Log Scroll Events", #selector(toggleLogging), checked: verbose))
        menu.addItem(item("Show Log", #selector(showLog)))
        menu.addItem(.separator())
        menu.addItem(item("Restart", #selector(restart)))
        menu.addItem(item("Quit Backspin", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
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
        alert.messageText = "Hide the Backspin menu bar icon?"
        alert.informativeText = """
            Backspin keeps running. To show the icon again, open Backspin again:

            open "\(Bundle.main.bundlePath)"
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
                try agent.remove()
            } else {
                try agent.install(executable: executablePath)
            }
            log("Start at login \(startsAtLogin ? "on" : "off")")
        } catch {
            log("Couldn't change start at login: \(error)")
        }
    }

    @objc func toggleAutoUpdate() {
        autoUpdate.toggle()
        defaults.set(autoUpdate, forKey: "autoUpdate")
        log("Install updates automatically \(autoUpdate ? "on" : "off")")
        checkForUpdatesAutomatically()
    }

    /// When automatic updates are on, checks once a day and installs any newer release.
    func checkForUpdatesAutomatically() {
        let lastCheck = defaults.object(forKey: "lastUpdateCheck") as? Date ?? .distantPast
        guard autoUpdate, canInstallUpdates, updateStatus == nil, Date().timeIntervalSince(lastCheck) > 24 * 60 * 60
        else { return }
        updateStatus = "Checking for Updates…"
        Task { @MainActor in
            defer { updateStatus = nil }
            do {
                if let release = try await newerRelease() { try await install(release) }
            } catch {
                log("Automatic update failed: \(error.localizedDescription)")
            }
        }
    }

    @objc func checkForUpdates() {
        updateStatus = "Checking for Updates…"
        Task { @MainActor in
            defer { updateStatus = nil }
            do {
                let release = try await newerRelease()
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                guard let release else {
                    alert.messageText = "Backspin is up to date"
                    alert.informativeText = "Version \(appVersion) is the latest."
                    alert.runModal()
                    return
                }
                alert.messageText = "Backspin \(release.version) is available"
                alert.informativeText = canInstallUpdates
                    ? "You have version \(appVersion)."
                    : "You have version \(appVersion). This copy was built from source, so it can't update itself."
                if canInstallUpdates { alert.addButton(withTitle: "Install and Restart") }
                alert.addButton(withTitle: "Release Notes")
                alert.addButton(withTitle: "Later")
                switch (alert.runModal(), canInstallUpdates) {
                case (.alertFirstButtonReturn, true): try await install(release)
                case (.alertFirstButtonReturn, false), (.alertSecondButtonReturn, true): NSWorkspace.shared.open(release.page)
                default: break
                }
            } catch {
                log("Update failed: \(error.localizedDescription)")
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert(error: error)
                alert.messageText = "Couldn't update Backspin"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    /// The latest release, if it's newer than this copy.
    @MainActor func newerRelease() async throws -> Release? {
        let release = try await Updater.latestRelease()
        defaults.set(Date(), forKey: "lastUpdateCheck")
        return release.version > appVersion ? release : nil
    }

    /// Replaces this copy with `release` and restarts into it.
    @MainActor func install(_ release: Release) async throws {
        updateStatus = "Installing Backspin \(release.version)…"
        log("Installing Backspin \(release.version)")
        try await Updater.install(release, replacing: Bundle.main.bundleURL)
        restart()
    }

    @objc func restart() {
        log("Restarting")
        var args = CommandLine.arguments.map { strdup($0) } + [nil]
        execv(executablePath, &args)
    }
}

// Keep the login item pointing at this copy if the app has moved.
if startsAtLogin { try? agent.install(executable: executablePath) }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
