import Foundation

enum AdtsSegmentAppenderError: Error, Equatable {
    case noSegments
    case segmentUnreadable(URL)
    case cannotOpenOutput
    case writeFailed(String)
    case renameFailed(String)
    case notAdts(URL)
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
/// the caller may delete the segments. It fails closed: if any segment cannot be read or is not
/// ADTS, or the disk refuses a write, the temp file is removed, the output is left as it was, and
/// the segments stay on disk. It needs free space for one more copy of the
/// recording; without it the join fails and the segments stay, for the caller to join later.
enum AdtsSegmentAppender {
    private static let chunkSize = 1 << 20

    @discardableResult
    static func append(_ segments: [URL], into outputURL: URL) throws -> UInt64 {
        guard !segments.isEmpty else { throw AdtsSegmentAppenderError.noSegments }
        let fileManager = FileManager.default
        let tempURL = outputURL.appendingPathExtension("appending")
        try? fileManager.removeItem(at: tempURL)
        guard fileManager.createFile(atPath: tempURL.path, contents: nil) else {
            throw AdtsSegmentAppenderError.cannotOpenOutput
        }
        guard let output = try? FileHandle(forWritingTo: tempURL) else {
            try? fileManager.removeItem(at: tempURL)
            throw AdtsSegmentAppenderError.cannotOpenOutput
        }

        var written: UInt64 = 0
        do {
            for segment in segments {
                written += try copy(segment, to: output)
            }
            try synchronizeAndClose(output)
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
        try synchronizeDirectory(of: outputURL)
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
    /// 12-bit sync word and carries its own length (13 bits, header included).
    static func wholeFramesLength(of input: FileHandle, segment: URL) throws -> UInt64 {
        do {
            let size = try input.seekToEnd()
            var position: UInt64 = 0
            while position + 7 <= size {
                try input.seek(toOffset: position)
                guard let data = try input.read(upToCount: 7), data.count == 7 else {
                    throw AdtsSegmentAppenderError.segmentUnreadable(segment)
                }
                let header = [UInt8](data)
                guard header[0] == 0xFF, header[1] & 0xF6 == 0xF0 else {
                    throw AdtsSegmentAppenderError.notAdts(segment)
                }
                let frameLength = (UInt64(header[3] & 0x03) << 11) | (UInt64(header[4]) << 3) | (UInt64(header[5]) >> 5)
                guard frameLength >= 7 else { throw AdtsSegmentAppenderError.notAdts(segment) }
                if position + frameLength > size { break }
                position += frameLength
            }
            return position
        } catch let error as AdtsSegmentAppenderError {
            throw error
        } catch {
            throw AdtsSegmentAppenderError.segmentUnreadable(segment)
        }
    }

    private static func synchronizeAndClose(_ handle: FileHandle) throws {
        do {
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw AdtsSegmentAppenderError.writeFailed(error.localizedDescription)
        }
    }

    /// Flushes the directory entry, so the rename itself survives a power loss.
    private static func synchronizeDirectory(of url: URL) throws {
        let descriptor = open(url.deletingLastPathComponent().path, O_RDONLY)
        guard descriptor >= 0, fsync(descriptor) == 0 else {
            if descriptor >= 0 { Darwin.close(descriptor) }
            throw AdtsSegmentAppenderError.writeFailed("Could not flush the directory of \(url.lastPathComponent).")
        }
        Darwin.close(descriptor)
    }
}
