import Foundation

enum AdtsSegmentAppenderError: Error, Equatable {
    case noSegments
    case segmentUnreadable(URL)
    case cannotOpenOutput
    case writeFailed(String)
    case renameFailed(String)
    case notAdts(URL)
    case noWholeFrame
}

/// Joins ADTS/AAC segments byte for byte.
///
/// ADTS is a stream of self-contained frames, each with its own header, so segments written with
/// the same encoder settings concatenate into one valid file: nothing is re-encoded, and nothing
/// depends on an export session that iOS may suspend in the background.
///
/// Only whole frames are copied. A segment can end inside a frame (written up to the moment the
/// app was killed); copied as is, that frame's header claims the first bytes of the next segment,
/// and AVFoundation stops decoding there, so everything after it would be lost.
///
/// `append` writes to a temp file next to the output, flushes it to storage and renames it into
/// place, then flushes the directory: once it returns, the joined file survives a power loss, so
/// the caller may delete the segments. It fails closed, and the segments always stay on disk: if
/// any segment cannot be read or is not ADTS, not one whole frame is found, or the disk refuses a
/// write, the temp file is removed and the output is left as it was; if the joined file cannot be
/// flushed after the rename, it is removed again. It needs free space for one more copy of the
/// recording; without it the join fails and the segments stay, for the caller to join later.
enum AdtsSegmentAppender {
    private static let chunkSize = 1 << 20

    /// The segments that go to the join: all but the ones known to be empty (an interruption that
    /// began before the first frame). A segment whose size cannot be read is not known to be empty,
    /// so it goes along, and the join fails closed on it instead of dropping it.
    static func segmentsToJoin(_ segments: [URL]) -> [URL] {
        segments.filter { byteCount(of: $0) != 0 }
    }

    /// The one segment that is the whole recording, when only one is left to join; `nil` when there
    /// are more. A sole segment whose size cannot be read (missing, unreadable) is no recording: it
    /// throws, so the caller keeps every segment instead of handing over nothing.
    static func soleRecording(in segments: [URL]) throws -> URL? {
        guard segments.count == 1 else { return nil }
        guard let size = byteCount(of: segments[0]), size > 0 else {
            throw AdtsSegmentAppenderError.segmentUnreadable(segments[0])
        }
        return segments[0]
    }

    private static func byteCount(of url: URL) -> Int64? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64
    }

    /// `flush` and `openForWriting` are there for tests, which make them fail; callers leave them.
    @discardableResult
    static func append(
        _ segments: [URL],
        into outputURL: URL,
        flush: (Int32) -> Bool = flushToStorage,
        openForWriting: (URL) -> FileHandle? = { try? FileHandle(forWritingTo: $0) }
    ) throws -> UInt64 {
        guard !segments.isEmpty else { throw AdtsSegmentAppenderError.noSegments }
        let fileManager = FileManager.default
        let tempURL = outputURL.appendingPathExtension("appending")
        try? fileManager.removeItem(at: tempURL)
        guard fileManager.createFile(atPath: tempURL.path, contents: nil) else {
            throw AdtsSegmentAppenderError.cannotOpenOutput
        }
        guard let output = openForWriting(tempURL) else {
            try? fileManager.removeItem(at: tempURL)
            throw AdtsSegmentAppenderError.cannotOpenOutput
        }

        var written: UInt64 = 0
        do {
            for segment in segments {
                written += try copy(segment, to: output)
            }
            // An empty file is no recording.
            guard written > 0 else { throw AdtsSegmentAppenderError.noWholeFrame }
            try synchronizeAndClose(output, flush: flush)
        } catch {
            try? output.close()
            try? fileManager.removeItem(at: tempURL)
            throw error
        }

        try? fileManager.removeItem(at: outputURL)
        do {
            try fileManager.moveItem(at: tempURL, to: outputURL)
        } catch {
            try? fileManager.removeItem(at: tempURL)
            throw AdtsSegmentAppenderError.renameFailed(error.localizedDescription)
        }
        do {
            try synchronizeDirectory(of: outputURL, flush: flush)
        } catch {
            // Not durable, so not done: the segments stay, and no joined copy is left beside them.
            try? fileManager.removeItem(at: outputURL)
            throw error
        }
        return written
    }

    /// Copies the whole frames of one segment to the end of `output`, with the throwing FileHandle
    /// API: the legacy `readData`/`write` raise Objective-C exceptions on an I/O error, which Swift
    /// cannot catch.
    @discardableResult
    private static func copy(_ segment: URL, to output: FileHandle) throws -> UInt64 {
        guard let input = try? FileHandle(forReadingFrom: segment) else {
            throw AdtsSegmentAppenderError.segmentUnreadable(segment)
        }
        defer { try? input.close() }
        let length = try wholeFramesLength(of: input, segment: segment)
        var remaining = length
        do {
            try input.seek(toOffset: 0)
        } catch {
            throw AdtsSegmentAppenderError.segmentUnreadable(segment)
        }
        while remaining > 0 {
            let chunk: Data
            do {
                let count = Int(min(UInt64(chunkSize), remaining))
                chunk = try autoreleasepool { try input.read(upToCount: count) } ?? Data()
            } catch {
                throw AdtsSegmentAppenderError.segmentUnreadable(segment)
            }
            // The file shrank while it was read: copy nothing half.
            guard !chunk.isEmpty else { throw AdtsSegmentAppenderError.segmentUnreadable(segment) }
            do {
                try output.write(contentsOf: chunk)
            } catch {
                throw AdtsSegmentAppenderError.writeFailed(error.localizedDescription)
            }
            remaining -= UInt64(chunk.count)
        }
        return length
    }

    /// The length of a segment up to the end of its last whole ADTS frame. Each frame starts with a
    /// 12-bit sync word and carries its own length (13 bits, header included). Read in chunks, so a
    /// long recording costs a few reads, not one per frame.
    static func wholeFramesLength(of input: FileHandle, segment: URL) throws -> UInt64 {
        do {
            try input.seek(toOffset: 0)
            var whole: UInt64 = 0
            var pending = Data()
            while true {
                let chunk = try autoreleasepool { try input.read(upToCount: chunkSize) } ?? Data()
                if chunk.isEmpty { break }
                pending.append(chunk)
                let consumed = try wholeFrames(in: pending, segment: segment)
                whole += UInt64(consumed)
                pending = Data(pending.dropFirst(consumed))
            }
            return whole
        } catch let error as AdtsSegmentAppenderError {
            throw error
        } catch {
            throw AdtsSegmentAppenderError.segmentUnreadable(segment)
        }
    }

    /// The bytes of the whole frames at the start of `data`; a frame that is not complete yet is left
    /// for the next chunk (or, at the end of the file, left out).
    private static func wholeFrames(in data: Data, segment: URL) throws -> Int {
        let bytes = [UInt8](data)
        var position = 0
        while position + 7 <= bytes.count {
            guard bytes[position] == 0xFF, bytes[position + 1] & 0xF6 == 0xF0 else {
                throw AdtsSegmentAppenderError.notAdts(segment)
            }
            let frameLength = (Int(bytes[position + 3] & 0x03) << 11) | (Int(bytes[position + 4]) << 3) | (Int(bytes[position + 5]) >> 5)
            guard frameLength >= 7 else { throw AdtsSegmentAppenderError.notAdts(segment) }
            if position + frameLength > bytes.count { break }
            position += frameLength
        }
        return position
    }

    private static func synchronizeAndClose(_ handle: FileHandle, flush: (Int32) -> Bool) throws {
        guard flush(handle.fileDescriptor) else {
            try? handle.close()
            throw AdtsSegmentAppenderError.writeFailed("Could not flush the joined file to storage.")
        }
        do {
            try handle.close()
        } catch {
            throw AdtsSegmentAppenderError.writeFailed(error.localizedDescription)
        }
    }

    /// `fsync` leaves the data in the drive's own cache on Apple platforms; `F_FULLFSYNC` empties
    /// it. A file system without `F_FULLFSYNC` falls back to `fsync`.
    static func flushToStorage(_ descriptor: Int32) -> Bool {
        fcntl(descriptor, F_FULLFSYNC) == 0 || fsync(descriptor) == 0
    }

    /// Flushes the directory entry, so the rename itself survives a power loss.
    private static func synchronizeDirectory(of url: URL, flush: (Int32) -> Bool) throws {
        let descriptor = open(url.deletingLastPathComponent().path, O_RDONLY)
        guard descriptor >= 0, flush(descriptor) else {
            if descriptor >= 0 { Darwin.close(descriptor) }
            throw AdtsSegmentAppenderError.writeFailed("Could not flush the directory of \(url.lastPathComponent).")
        }
        Darwin.close(descriptor)
    }
}
