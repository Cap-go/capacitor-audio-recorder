import XCTest
@testable import CapacitorAudioRecorderPlugin

final class CapacitorAudioRecorderPluginTests: XCTestCase {
    func testPluginInitialises() {
        let plugin = CapacitorAudioRecorderPlugin()
        XCTAssertEqual(plugin.identifier, "CapacitorAudioRecorderPlugin")
    }
}
