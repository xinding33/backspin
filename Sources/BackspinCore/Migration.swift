import Foundation

/// Start at Login is a LaunchAgent, which also relaunches the app if it crashes.
public struct LaunchAgent {
    public let label: String
    public let url: URL

    public init(label: String, directory: URL) {
        self.label = label
        url = directory.appendingPathComponent("\(label).plist")
    }

    public var isInstalled: Bool { FileManager.default.fileExists(atPath: url.path) }

    public func install(executable: String) throws {
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],
            "ProcessType": "Interactive",
        ]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: url)
    }

    public func remove() throws {
        try FileManager.default.removeItem(at: url)
    }
}

/// Moves state left by an earlier name of the app (Backspin was ScrollFlip before 1.3.0).
/// Each step does nothing once the old state is gone, so it's safe to run at every launch.
public enum LegacyMigration {
    /// Renames the old log, unless there's already a new one.
    public static func moveLog(from old: URL, to new: URL) {
        let files = FileManager.default
        guard files.fileExists(atPath: old.path), !files.fileExists(atPath: new.path) else { return }
        try? files.moveItem(at: old, to: new)
    }

    /// Whether the old preferences domain has any settings. Once removed, it reads as empty, not nil.
    public static func hasSettings(in oldDomain: String, _ defaults: UserDefaults) -> Bool {
        !(defaults.persistentDomain(forName: oldDomain) ?? [:]).isEmpty
    }

    /// Copies the settings `defaults` doesn't have yet from the old preferences domain, then
    /// deletes that domain. Returns whether there were any.
    @discardableResult
    public static func moveSettings(from oldDomain: String, to defaults: UserDefaults) -> Bool {
        guard let old = defaults.persistentDomain(forName: oldDomain), !old.isEmpty else { return false }
        for (key, value) in old where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
        defaults.removePersistentDomain(forName: oldDomain)
        return true
    }

    /// Turns Start at Login on for the new agent if the old one had it, then removes the old
    /// agent. Doesn't load or unload anything in launchd. Returns whether there was an old agent.
    @discardableResult
    public static func moveLaunchAgent(from old: LaunchAgent, to new: LaunchAgent, executable: String) throws -> Bool {
        guard old.isInstalled else { return false }
        if !new.isInstalled { try new.install(executable: executable) }
        try old.remove()
        return true
    }
}
