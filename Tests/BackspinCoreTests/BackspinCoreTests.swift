import BackspinCore
import CoreGraphics
import XCTest

final class FlipTests: XCTestCase {
    func scrollEvent() -> CGEvent {
        CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 3, wheel2: -2, wheel3: 0)!
    }

    func deltas(_ event: CGEvent) -> [Double] {
        [
            Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)),
            event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1),
            Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)),
            Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2)),
            event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2),
            Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)),
        ]
    }

    func testFlipsOnlyTheChosenAxes() {
        let original = deltas(scrollEvent())
        XCTAssertEqual(original[0], 3)
        XCTAssertEqual(original[3], -2)
        for (vertical, horizontal) in [(true, true), (true, false), (false, true), (false, false)] {
            let event = scrollEvent()
            flip(event, vertical: vertical, horizontal: horizontal)
            let signs = Array(repeating: vertical ? -1.0 : 1, count: 3) + Array(repeating: horizontal ? -1.0 : 1, count: 3)
            XCTAssertEqual(deltas(event), zip(original, signs).map(*), "vertical: \(vertical), horizontal: \(horizontal)")
        }
    }
}

final class MigrationTests: XCTestCase {
    var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: folder)
    }

    func testLaunchAgentStartsAtLoginAndRelaunchesAfterCrashes() throws {
        let agent = LaunchAgent(label: "test.backspin", directory: folder.appendingPathComponent("LaunchAgents"))
        XCTAssertFalse(agent.isInstalled)
        try agent.install(executable: "/Applications/Backspin.app/Contents/MacOS/Backspin")
        let plist = try XCTUnwrap(NSDictionary(contentsOf: agent.url))
        XCTAssertEqual(plist["Label"] as? String, "test.backspin")
        XCTAssertEqual(plist["ProgramArguments"] as? [String], ["/Applications/Backspin.app/Contents/MacOS/Backspin"])
        XCTAssertEqual(plist["RunAtLoad"] as? Bool, true)
        XCTAssertEqual(plist["KeepAlive"] as? [String: Bool], ["SuccessfulExit": false])
        try agent.remove()
        XCTAssertFalse(agent.isInstalled)
    }

    func testMovesStartAtLoginToTheNewAgent() throws {
        let old = LaunchAgent(label: "test.scrollflip", directory: folder)
        let new = LaunchAgent(label: "test.backspin", directory: folder)
        try old.install(executable: "/opt/homebrew/opt/scrollflip/ScrollFlip.app/Contents/MacOS/ScrollFlip")
        XCTAssertTrue(try LegacyMigration.moveLaunchAgent(from: old, to: new, executable: "/Applications/Backspin.app/Contents/MacOS/Backspin"))
        XCTAssertFalse(old.isInstalled)
        let plist = try XCTUnwrap(NSDictionary(contentsOf: new.url))
        XCTAssertEqual(plist["Label"] as? String, "test.backspin")
        XCTAssertEqual(plist["ProgramArguments"] as? [String], ["/Applications/Backspin.app/Contents/MacOS/Backspin"])
        XCTAssertFalse(try LegacyMigration.moveLaunchAgent(from: old, to: new, executable: "/elsewhere"))
    }

    func testLeavesStartAtLoginOffWithoutAnOldAgent() throws {
        let old = LaunchAgent(label: "test.scrollflip", directory: folder)
        let new = LaunchAgent(label: "test.backspin", directory: folder)
        XCTAssertFalse(try LegacyMigration.moveLaunchAgent(from: old, to: new, executable: "/Applications/Backspin.app"))
        XCTAssertFalse(new.isInstalled)
    }

    func testMovesSettingsWithoutOverwritingNewerOnes() throws {
        let domain = "test.backspin.\(UUID().uuidString)", oldDomain = "test.scrollflip.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.setPersistentDomain(["enabled": false, "reverseHorizontal": false, "iconHidden": true], forName: oldDomain)
        defaults.set(false, forKey: "iconHidden")
        XCTAssertTrue(LegacyMigration.hasSettings(in: oldDomain, defaults))

        XCTAssertTrue(LegacyMigration.moveSettings(from: oldDomain, to: defaults))
        XCTAssertEqual(defaults.object(forKey: "enabled") as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: "reverseHorizontal") as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: "iconHidden") as? Bool, false)
        XCTAssertNil(defaults.object(forKey: "reverseVertical"))
        XCTAssertFalse(LegacyMigration.hasSettings(in: oldDomain, defaults))
        XCTAssertFalse(LegacyMigration.moveSettings(from: oldDomain, to: defaults))
    }

    func testMovesTheLogUnlessThereIsANewOne() throws {
        let old = folder.appendingPathComponent("ScrollFlip.log"), new = folder.appendingPathComponent("Backspin.log")
        try "old\n".write(to: old, atomically: true, encoding: .utf8)
        LegacyMigration.moveLog(from: old, to: new)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertEqual(try String(contentsOf: new, encoding: .utf8), "old\n")

        try "older\n".write(to: old, atomically: true, encoding: .utf8)
        LegacyMigration.moveLog(from: old, to: new)
        XCTAssertEqual(try String(contentsOf: new, encoding: .utf8), "old\n")
    }
}

final class UpdateTests: XCTestCase {
    var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: folder)
    }

    func testComparesVersionsNumerically() throws {
        func version(_ string: String) throws -> Version { try XCTUnwrap(Version(string)) }
        XCTAssertLessThan(try version("1.9.0"), try version("1.10.0"))
        XCTAssertLessThan(try version("1.3.0"), try version("v1.3.1"))
        XCTAssertEqual(try version("v1.3"), try version("1.3.0"))
        XCTAssertEqual(try version("v1.3.0").description, "1.3.0")
        XCTAssertNil(Version("1.3.0-beta"))
        XCTAssertNil(Version(""))
    }

    func testFindsTheDownloadInTheLatestRelease() throws {
        let json = """
            {"tag_name": "v1.4.0", "html_url": "https://github.com/xinding33/backspin/releases/tag/v1.4.0",
             "assets": [
               {"name": "notes.txt", "browser_download_url": "https://example.com/notes.txt"},
               {"name": "Backspin-1.4.0.zip",
                "browser_download_url": "https://github.com/xinding33/backspin/releases/download/v1.4.0/Backspin-1.4.0.zip"}]}
            """
        let release = try Release(gitHubJSON: Data(json.utf8))
        XCTAssertEqual(release.version, Version("1.4.0"))
        XCTAssertEqual(release.page.absoluteString, "https://github.com/xinding33/backspin/releases/tag/v1.4.0")
        XCTAssertEqual(release.download.lastPathComponent, "Backspin-1.4.0.zip")

        let noZip = #"{"tag_name": "v1.4.0", "html_url": "https://example.com", "assets": []}"#
        XCTAssertThrowsError(try Release(gitHubJSON: Data(noZip.utf8)))
    }

    /// Makes an ad-hoc signed Backspin.app whose designated requirement is just its identifier.
    func makeApp(in name: String, identifier: String = "test.backspin", version: String) throws -> URL {
        let app = folder.appendingPathComponent(name).appendingPathComponent("Backspin.app")
        let macOS = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: "/usr/bin/true", toPath: macOS.appendingPathComponent("Backspin").path)
        let info: NSDictionary = [
            "CFBundleIdentifier": identifier, "CFBundleExecutable": "Backspin",
            "CFBundlePackageType": "APPL", "CFBundleShortVersionString": version,
        ]
        try info.write(to: app.appendingPathComponent("Contents/Info.plist"))
        try shell("/usr/bin/codesign", "--force", "--sign", "-", "-r=designated => identifier \"\(identifier)\"", app.path)
        return app
    }

    /// Zips `app` the way releases are.
    func zip(_ app: URL) throws -> URL {
        let zip = app.deletingLastPathComponent().appendingPathComponent("Backspin.zip")
        try shell("/usr/bin/ditto", "-c", "-k", "--keepParent", app.path, zip.path)
        return zip
    }

    func shell(_ path: String, _ arguments: String...) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "\(path) \(arguments)")
    }

    func installedVersion(_ app: URL) -> String? {
        NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String
    }

    func testInstallsAnUpdateSignedLikeTheApp() throws {
        let app = try makeApp(in: "installed", version: "1.3.0")
        let update = try zip(makeApp(in: "update", version: "1.4.0"))
        try Updater.install(zip: update, version: XCTUnwrap(Version("1.4.0")), replacing: app)
        XCTAssertEqual(installedVersion(app), "1.4.0")
    }

    func testRejectsAnUpdateSignedDifferently() throws {
        let app = try makeApp(in: "installed", version: "1.3.0")
        let update = try zip(makeApp(in: "update", identifier: "test.impostor", version: "1.4.0"))
        XCTAssertThrowsError(try Updater.install(zip: update, version: XCTUnwrap(Version("1.4.0")), replacing: app)) {
            XCTAssertEqual($0 as? UpdateError, .badSignature)
        }
        XCTAssertEqual(installedVersion(app), "1.3.0")
    }

    func testRejectsAnUpdateThatIsTheWrongVersion() throws {
        let app = try makeApp(in: "installed", version: "1.3.0")
        let update = try zip(makeApp(in: "update", version: "1.2.0"))
        XCTAssertThrowsError(try Updater.install(zip: update, version: XCTUnwrap(Version("1.4.0")), replacing: app)) {
            XCTAssertEqual($0 as? UpdateError, .wrongVersion)
        }
        XCTAssertEqual(installedVersion(app), "1.3.0")
    }

    func testRejectsAModifiedUpdate() throws {
        let app = try makeApp(in: "installed", version: "1.3.0")
        let update = try makeApp(in: "update", version: "1.4.0")
        try Data("tampered".utf8).write(to: update.appendingPathComponent("Contents/MacOS/Backspin"))
        XCTAssertThrowsError(try Updater.install(zip: zip(update), version: XCTUnwrap(Version("1.4.0")), replacing: app)) {
            XCTAssertEqual($0 as? UpdateError, .badSignature)
        }
        XCTAssertEqual(installedVersion(app), "1.3.0")
    }

    func testSourceBuildsAreNotDeveloperIDSigned() throws {
        XCTAssertFalse(Updater.isDeveloperIDSigned(try makeApp(in: "installed", version: "1.3.0")))
    }
}
