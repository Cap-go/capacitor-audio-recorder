import AVFoundation
import XCTest
@testable import CapacitorAudioRecorderPlugin

final class AudioSegmentMergerTests: XCTestCase {
    func testPreferredFallbackSegment_prefersLongestUsableDuration() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CapacitorAudioRecorderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let shortURL = directory.appendingPathComponent("short.m4a")
        let longURL = directory.appendingPathComponent("long.m4a")
        let emptyURL = directory.appendingPathComponent("empty.m4a")
        try writeSilentM4A(at: shortURL, durationSeconds: 0.05)
        try writeSilentM4A(at: longURL, durationSeconds: 0.2)
        try Data().write(to: emptyURL)

        let fallback = AudioSegmentMerger.preferredFallbackSegment(from: [shortURL, emptyURL, longURL])
        XCTAssertEqual(fallback, longURL)
    }

    func testMergeSegments_skipsEmptySegments() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CapacitorAudioRecorderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstURL = directory.appendingPathComponent("first.m4a")
        let emptyURL = directory.appendingPathComponent("empty.m4a")
        let secondURL = directory.appendingPathComponent("second.m4a")
        let outputURL = directory.appendingPathComponent("merged.m4a")
        try writeSilentM4A(at: firstURL, durationSeconds: 0.1)
        try Data().write(to: emptyURL)
        try writeSilentM4A(at: secondURL, durationSeconds: 0.1)

        let duration = try AudioSegmentMerger.mergeSegments([firstURL, emptyURL, secondURL], into: outputURL)
        XCTAssertGreaterThan(duration, 150)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    }

    private func writeSilentM4A(at url: URL, durationSeconds: Double) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.prepareToRecord()
        XCTAssertTrue(recorder.record(forDuration: durationSeconds))
        recorder.stop()
    }
}
