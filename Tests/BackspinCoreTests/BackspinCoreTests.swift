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
