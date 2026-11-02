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
        AdtsSegmentAppender.flush = AdtsSegmentAppender.flushToStorage
        AdtsSegmentAppender.openForWriting = { try? FileHandle(forWritingTo: $0) }
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

    /// An interruption that begins before the first frame leaves a 0-byte segment: it adds nothing.
    func testAppend_anEmptySegmentAddsNothing() throws {
        let first = try writeTone(named: "first.aac", seconds: 1.0)
        let empty = directory.appendingPathComponent("empty.aac")
        try Data().write(to: empty)
        let second = try writeTone(named: "second.aac", seconds: 1.0)
        let output = directory.appendingPathComponent("joined.aac")

        try AdtsSegmentAppender.append([first, empty, second], into: output)

        XCTAssertEqual(try Data(contentsOf: output), try Data(contentsOf: first) + Data(contentsOf: second))
        XCTAssertEqual(decodedSeconds(output), decodedSeconds(first) + decodedSeconds(second), accuracy: 0.05)
    }

    /// A segment that ends inside a frame: copied as is, that frame would swallow the start of the
    /// next segment and AVFoundation would stop decoding there. Only its whole frames are joined.
    /// Cut 5 bytes in, the header is not whole yet; cut 20 bytes in, it is whole and claims bytes
    /// that never came.
    func testAppend_aSegmentCutInsideAFrameKeepsTheNextSegment() throws {
        let bytes = try Data(contentsOf: try writeTone(named: "whole.aac", seconds: 2.0))
        let frames = adtsFrameOffsets(bytes)
        let lastWhole = frames.count / 2
        let second = try writeTone(named: "second.aac", seconds: 2.0)
        for into in [5, 20] {
            let cut = directory.appendingPathComponent("cut-\(into).aac")
            try bytes.prefix(frames[lastWhole] + into).write(to: cut)
            let output = directory.appendingPathComponent("joined-\(into).aac")

            try AdtsSegmentAppender.append([cut, second], into: output)

            XCTAssertEqual(try Data(contentsOf: output), try bytes.prefix(frames[lastWhole]) + Data(contentsOf: second))
            let wholeFramesSeconds = Double(lastWhole * 1024) / 44_100
            XCTAssertEqual(decodedSeconds(output), wholeFramesSeconds + decodedSeconds(second), accuracy: 3 * 1024.0 / 44_100)
        }
    }

    /// A segment longer than one read chunk (1 MiB): frames that straddle a chunk boundary are
    /// carried over, and the cut at the end is still found.
    func testAppend_aLongSegmentIsScannedAcrossChunks() throws {
        let long = try writeTone(named: "long.aac", seconds: 200.0)
        let bytes = try Data(contentsOf: long)
        XCTAssertGreaterThan(bytes.count, 1 << 20)
        let frames = adtsFrameOffsets(bytes)
        let lastWhole = frames.count - 2
        let cut = directory.appendingPathComponent("long-cut.aac")
        try bytes.prefix(frames[lastWhole] + 20).write(to: cut)
        let second = try writeTone(named: "second.aac", seconds: 1.0)
        let output = directory.appendingPathComponent("joined.aac")

        try AdtsSegmentAppender.append([cut, second], into: output)

        XCTAssertEqual(try Data(contentsOf: output), try bytes.prefix(frames[lastWhole]) + Data(contentsOf: second))
    }

    /// Segments that end before their first frame is whole: an empty file is no recording.
    func testAppend_notOneWholeFrameIsAFailureAndTheSegmentsStay() throws {
        let bytes = try Data(contentsOf: try writeTone(named: "whole.aac", seconds: 1.0))
        let frames = adtsFrameOffsets(bytes)
        let cut = directory.appendingPathComponent("cut.aac")
        try bytes.prefix(frames[1] - 3).write(to: cut)
        let output = directory.appendingPathComponent("joined.aac")

        XCTAssertThrowsError(try AdtsSegmentAppender.append([cut, cut], into: output)) { error in
            XCTAssertEqual(error as? AdtsSegmentAppenderError, .noWholeFrame)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathExtension("appending").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cut.path))
    }

    /// The segments may only go once the joined file is on storage: a flush that fails is a failed
    /// join, with no joined file left behind.
    func testAppend_aFlushThatFailsLeavesNoJoinedFile() throws {
        let first = try writeTone(named: "first.aac", seconds: 0.5)
        let second = try writeTone(named: "second.aac", seconds: 0.5)
        let output = directory.appendingPathComponent("joined.aac")
        AdtsSegmentAppender.flush = { _ in false }

        XCTAssertThrowsError(try AdtsSegmentAppender.append([first, second], into: output))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathExtension("appending").path))
    }

    /// The flush of the directory, after the rename, fails: the joined file is removed again, so no
    /// copy is left that nobody reports.
    func testAppend_aDirectoryFlushThatFailsRemovesTheJoinedFile() throws {
        let first = try writeTone(named: "first.aac", seconds: 0.5)
        let second = try writeTone(named: "second.aac", seconds: 0.5)
        let output = directory.appendingPathComponent("joined.aac")
        var flushes = 0
        AdtsSegmentAppender.flush = { _ in
            flushes += 1
            return flushes == 1
        }

        XCTAssertThrowsError(try AdtsSegmentAppender.append([first, second], into: output))
        XCTAssertEqual(flushes, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
    }

    /// The temp file was made but cannot be opened: it is removed again, not left beside the output.
    func testAppend_aTempFileThatCannotBeOpenedIsRemoved() throws {
        let first = try writeTone(named: "first.aac", seconds: 0.5)
        let output = directory.appendingPathComponent("joined.aac")
        AdtsSegmentAppender.openForWriting = { _ in nil }

        XCTAssertThrowsError(try AdtsSegmentAppender.append([first], into: output))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathExtension("appending").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
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

        XCTAssertEqual(AdtsSegmentAppender.segmentsToJoin([withAudio, empty, missing]), [withAudio, missing])
    }

    /// One segment left is the recording only if it can be read; an unreadable one is a failure,
    /// not a recording of nothing that costs the other segments.
    func testSoleRecording_isOnlyASegmentThatCanBeRead() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sole-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let withAudio = directory.appendingPathComponent("a.aac")
        try Data([0xFF, 0xF1, 0x50]).write(to: withAudio)
        let missing = directory.appendingPathComponent("b.aac")

        XCTAssertEqual(try AdtsSegmentAppender.soleRecording(in: [withAudio]), withAudio)
        XCTAssertNil(try AdtsSegmentAppender.soleRecording(in: [withAudio, missing]))
        XCTAssertThrowsError(try AdtsSegmentAppender.soleRecording(in: [missing]))
    }

    func testFlushToStorage_flushesARealFileAndRefusesABadDescriptor() throws {
        let file = try writeTone(named: "flush.aac", seconds: 0.2)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        XCTAssertTrue(AdtsSegmentAppender.flushToStorage(handle.fileDescriptor))
        XCTAssertFalse(AdtsSegmentAppender.flushToStorage(-1))
    }

    /// The duration reported with mergeFailed: ADTS has no index, so with a variable bit rate and a
    /// quiet start an estimate from the first frames is wrong. The precise read counts the whole file.
    func testFallbackDuration_ofAnAacSegmentIsItsLength() throws {
        let segment = try writeSamples(named: "segment.aac", seconds: 20.0, variableBitRate: true) { index in
            index < 5 * 44_100 ? 0 : Float.random(in: -0.5...0.5)
        }
        let plays = decodedSeconds(segment) * 1000

        let duration = CapacitorAudioRecorderPlugin.fallbackDurationMilliseconds(for: segment, fileExtension: "aac")

        // Within three frames: the precise read leaves out the encoder's priming (2112 samples, 48 ms),
        // which the decoder still hands out. The estimate is 4 s off here (24.5 s for 20 s).
        XCTAssertEqual(duration, plays, accuracy: 3 * 1024 / 44.1)
    }

    func testAppend_failsClosedOnASegmentThatIsNotAdts() throws {
        let first = try writeTone(named: "first.aac", seconds: 0.5)
        let mpeg4 = try writeTone(named: "other.m4a", seconds: 0.5)
        let output = directory.appendingPathComponent("joined.aac")

        XCTAssertThrowsError(try AdtsSegmentAppender.append([first, mpeg4], into: output)) { error in
            XCTAssertEqual(error as? AdtsSegmentAppenderError, .notAdts(mpeg4))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathExtension("appending").path))
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
    private func writeTone(named name: String, seconds: Double, amplitude: Double = 0.3) throws -> URL {
        try writeSamples(named: name, seconds: seconds) { index in Float(sin(Double(index) * 2 * .pi * 440 / 44_100) * amplitude) }
    }

    private func writeNoise(named name: String, seconds: Double) throws -> URL {
        try writeSamples(named: name, seconds: seconds) { _ in Float.random(in: -0.5...0.5) }
    }

    private func writeSamples(named name: String, seconds: Double, variableBitRate: Bool = false, sample: (Int) -> Float) throws -> URL {
        let url = directory.appendingPathComponent(name)
        var settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1
        ]
        if variableBitRate {
            settings[AVEncoderBitRateStrategyKey] = AVAudioBitRateStrategy_Variable
        }
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let frames = AVAudioFrameCount(seconds * 44_100)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let samples = buffer.floatChannelData![0]
        for index in 0..<Int(frames) {
            samples[index] = sample(index)
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
