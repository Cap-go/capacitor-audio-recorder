import AVFoundation
import XCTest
@testable import CapacitorAudioRecorderPlugin

final class AdtsSegmentAppenderTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AdtsSegmentAppenderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testAppend_joinsSegmentsByteForByteIntoOnePlayableFile() throws {
        let first = try writeTone(named: "first.aac", seconds: 1.0)
        let second = try writeTone(named: "second.aac", seconds: 2.0)
        let output = directory.appendingPathComponent("joined.aac")

        let written = try AdtsSegmentAppender.append([first, second], into: output)

        let expected = try Data(contentsOf: first) + Data(contentsOf: second)
        XCTAssertEqual(try Data(contentsOf: output), expected)
        XCTAssertEqual(written, UInt64(expected.count))
        XCTAssertEqual(decodedSeconds(output), decodedSeconds(first) + decodedSeconds(second), accuracy: 0.05)
    }

    func testAppend_failsClosedWhenASegmentIsMissing() throws {
        let first = try writeTone(named: "first.aac", seconds: 0.5)
        let missing = directory.appendingPathComponent("missing.aac")
        let output = directory.appendingPathComponent("joined.aac")
        let before = try Data(contentsOf: first)

        XCTAssertThrowsError(try AdtsSegmentAppender.append([first, missing], into: output)) { error in
            XCTAssertEqual(error as? AdtsSegmentAppenderError, .segmentUnreadable(missing))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathExtension("appending").path))
        XCTAssertEqual(try Data(contentsOf: first), before)
    }

    func testAppend_leavesAnExistingOutputAloneWhenItFails() throws {
        let output = directory.appendingPathComponent("joined.aac")
        try Data([1, 2, 3]).write(to: output)

        XCTAssertThrowsError(try AdtsSegmentAppender.append([directory.appendingPathComponent("gone.aac")], into: output))
        XCTAssertEqual(try Data(contentsOf: output), Data([1, 2, 3]))
    }

    /// What a hard kill leaves behind: the file stops in the middle of a frame. ADTS still plays up
    /// to the last whole frame; MPEG-4 without its closing `moov` plays nothing.
    func testUnfinishedFile_adtsDecodesToTheLastWholeFrame_mpeg4DecodesNothing() throws {
        let adts = try writeTone(named: "whole.aac", seconds: 3.0)
        let bytes = try Data(contentsOf: adts)
        let frames = adtsFrameOffsets(bytes)
        XCTAssertGreaterThan(frames.count, 100)
        let lastWhole = frames.count / 2
        let cutAt = frames[lastWhole] + 5 // five bytes into the next frame
        let cut = directory.appendingPathComponent("cut.aac")
        try bytes.prefix(cutAt).write(to: cut)

        let wholeFramesSeconds = Double(lastWhole * 1024) / 44_100
        XCTAssertEqual(decodedSeconds(cut), wholeFramesSeconds, accuracy: 2 * 1024.0 / 44_100)

        let mpeg4 = try writeTone(named: "whole.m4a", seconds: 3.0)
        let mpeg4Bytes = try Data(contentsOf: mpeg4)
        let mpeg4Cut = directory.appendingPathComponent("cut.m4a")
        try mpeg4Bytes.prefix(mpeg4Bytes.count / 2).write(to: mpeg4Cut)
        XCTAssertEqual(decodedSeconds(mpeg4Cut), 0, accuracy: 0.001)
    }

    // MARK: - Helpers

    /// AVFoundation picks the container from the extension: `.aac` writes ADTS, `.m4a` MPEG-4.
    private func writeTone(named name: String, seconds: Double) throws -> URL {
        let url = directory.appendingPathComponent(name)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1
        ]
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let frames = AVAudioFrameCount(seconds * 44_100)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let samples = buffer.floatChannelData![0]
        for index in 0..<Int(frames) {
            samples[index] = Float(sin(Double(index) * 2 * .pi * 440 / 44_100) * 0.3)
        }
        let file = try AVAudioFile(forWriting: url, settings: settings)
        try file.write(from: buffer)
        return url
    }

    /// Decodes for real, until the end or the first error: what survives is what plays.
    private func decodedSeconds(_ url: URL) -> Double {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096)!
        var decoded: AVAudioFramePosition = 0
        while (try? file.read(into: buffer)) != nil, buffer.frameLength > 0 {
            decoded += AVAudioFramePosition(buffer.frameLength)
        }
        return Double(decoded) / file.processingFormat.sampleRate
    }

    /// Byte offsets of the ADTS frames: a 12-bit sync word, then a 13-bit frame length.
    private func adtsFrameOffsets(_ data: Data) -> [Int] {
        let bytes = [UInt8](data)
        var offsets: [Int] = []
        var position = 0
        while position + 7 <= bytes.count, bytes[position] == 0xFF, bytes[position + 1] & 0xF0 == 0xF0 {
            offsets.append(position)
            let length = (Int(bytes[position + 3] & 0x03) << 11) | (Int(bytes[position + 4]) << 3) | (Int(bytes[position + 5]) >> 5)
            guard length > 0 else { break }
            position += length
        }
        return offsets
    }
}
