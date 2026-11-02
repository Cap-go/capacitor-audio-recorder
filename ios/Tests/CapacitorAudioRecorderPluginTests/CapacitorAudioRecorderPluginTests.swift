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

    /// Only a segment known to be empty stays out of the join; one whose size cannot be read goes
    /// along, so the join fails closed on it instead of dropping it.
    func testSegmentsToJoin_leaveOutOnlyWhatIsKnownToBeEmpty() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("segments-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let withAudio = directory.appendingPathComponent("a.aac")
        try Data([0xFF, 0xF1, 0x50]).write(to: withAudio)
        let empty = directory.appendingPathComponent("b.aac")
        try Data().write(to: empty)
        let missing = directory.appendingPathComponent("c.aac")

        XCTAssertEqual(CapacitorAudioRecorderPlugin.segmentsToJoin([withAudio, empty, missing]), [withAudio, missing])
    }
}
