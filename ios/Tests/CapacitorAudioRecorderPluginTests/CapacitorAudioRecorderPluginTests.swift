import XCTest
@testable import CapacitorAudioRecorderPlugin

final class CapacitorAudioRecorderPluginTests: XCTestCase {
    func testPluginInitialises() {
        let plugin = CapacitorAudioRecorderPlugin()
        XCTAssertEqual(plugin.identifier, "CapacitorAudioRecorderPlugin")
    }

    func testAFailedStartGivesTheAudioSessionBack() {
        let plugin = CapacitorAudioRecorderPlugin()
        var deactivated = 0
        plugin.deactivateSession = { deactivated += 1 }

        plugin.handleFailedStart()

        XCTAssertEqual(deactivated, 1)
    }
}
