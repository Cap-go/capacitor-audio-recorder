import Foundation

enum AdtsSegmentAppenderError: Error, Equatable {
    case noSegments
    case segmentUnreadable(URL)
    case cannotOpenOutput
    case writeFailed(String)
    case renameFailed(String)
}

/// Joins ADTS/AAC segments byte for byte.
///
/// ADTS is a stream of self-contained frames, each with its own header, so segments written with
/// the same encoder settings concatenate into one valid file: nothing is re-encoded, and nothing
/// depends on an export session that iOS may suspend in the background.
///
/// `append` writes to a temp file next to the output and renames it into place. It fails closed:
/// if any segment cannot be read or the disk refuses a write, the temp file is removed, the output
/// is left as it was, and the segments stay on disk. It needs free space for one more copy of the
/// recording; `appendInPlace` is for when that space is not there.
enum AdtsSegmentAppender {
    private static let chunkSize = 1 << 20

    @discardableResult
    static func append(_ segments: [URL], into outputURL: URL) throws -> UInt64 {
        guard !segments.isEmpty else { throw AdtsSegmentAppenderError.noSegments }
        let fileManager = FileManager.default
        let tempURL = outputURL.appendingPathExtension("appending")
        try? fileManager.removeItem(at: tempURL)
        guard fileManager.createFile(atPath: tempURL.path, contents: nil),
              let output = try? FileHandle(forWritingTo: tempURL) else {
            throw AdtsSegmentAppenderError.cannotOpenOutput
        }

        var written: UInt64 = 0
        do {
            for segment in segments {
                written += try copy(segment, to: output)
            }
            try close(output)
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
        return written
    }

    /// The join for a full disk: the other segments are appended onto the first, and each is
    /// deleted as soon as it is in, so the extra space needed is never more than one chunk. Not
    /// atomic: interrupted half way, the first segment holds part of the next one while that one
    /// is still on disk. A later join then repeats that part — audio twice, never audio lost.
    /// Returns the first segment, which is now the recording.
    @discardableResult
    static func appendInPlace(_ segments: [URL]) throws -> URL {
        guard let first = segments.first else { throw AdtsSegmentAppenderError.noSegments }
        guard let output = try? FileHandle(forWritingTo: first) else {
            throw AdtsSegmentAppenderError.segmentUnreadable(first)
        }
        do {
            try output.seekToEnd()
            for segment in segments.dropFirst() {
                try copy(segment, to: output)
                try output.synchronize()
                try? FileManager.default.removeItem(at: segment)
            }
            try close(output)
        } catch {
            try? output.close()
            throw error
        }
        return first
    }

    /// Copies one segment to the end of `output`, with the throwing FileHandle API: the legacy
    /// `readData`/`write` raise Objective-C exceptions on an I/O error, which Swift cannot catch.
    @discardableResult
    private static func copy(_ segment: URL, to output: FileHandle) throws -> UInt64 {
        guard let input = try? FileHandle(forReadingFrom: segment) else {
            throw AdtsSegmentAppenderError.segmentUnreadable(segment)
        }
        defer { try? input.close() }
        var copied: UInt64 = 0
        while true {
            let chunk: Data
            do {
                chunk = try autoreleasepool { try input.read(upToCount: chunkSize) } ?? Data()
            } catch {
                throw AdtsSegmentAppenderError.segmentUnreadable(segment)
            }
            if chunk.isEmpty { break }
            do {
                try output.write(contentsOf: chunk)
            } catch {
                throw AdtsSegmentAppenderError.writeFailed(error.localizedDescription)
            }
            copied += UInt64(chunk.count)
        }
        return copied
    }

    private static func close(_ handle: FileHandle) throws {
        do {
            try handle.close()
        } catch {
            throw AdtsSegmentAppenderError.writeFailed(error.localizedDescription)
        }
    }
}
