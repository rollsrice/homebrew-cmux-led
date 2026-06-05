import XCTest
@testable import cmux_led

final class LEDModeTests: XCTestCase {
    private let suiteName = "LEDModeTests.suite"

    private func freshDefaults() -> UserDefaults {
        let d = UserDefaults(suiteName: suiteName)!
        d.removePersistentDomain(forName: suiteName)
        return d
    }

    func testDefaultsToWorkspacesWhenUnset() {
        let d = freshDefaults()
        XCTAssertEqual(LEDMode.load(from: d), .workspaces)
    }

    func testRoundTripsThroughDefaults() {
        let d = freshDefaults()
        LEDMode.surfaces.save(to: d)
        XCTAssertEqual(LEDMode.load(from: d), .surfaces)
        LEDMode.workspaces.save(to: d)
        XCTAssertEqual(LEDMode.load(from: d), .workspaces)
    }

    func testIgnoresGarbageStoredValue() {
        let d = freshDefaults()
        d.set("nonsense", forKey: "ledMode")
        XCTAssertEqual(LEDMode.load(from: d), .workspaces)
    }
}
