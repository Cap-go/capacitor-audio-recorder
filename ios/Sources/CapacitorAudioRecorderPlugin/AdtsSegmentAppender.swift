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
/// depends on an export session that iOS may suspend in the background. The write goes to a temp
/// file next to the output and is renamed into place, and it fails closed: if any segment cannot
/// be read, the temp file is removed, the output is left as it was, and the segments stay on disk.
enum AdtsSegmentAppender {
    @discardableResult
    static func append(_ segments: [URL], into outputURL: URL) throws -> UInt64 {
        guard !segments.isEmpty else { throw AdtsSegmentAppenderError.noSegments }
        let fileManager = FileManager.default
        let tempURL = outputURL.appendingPathExtension("appending")
        try? fileManager.removeItem(at: tempURL)
        guard fileManager.createFile(atPath: tempURL.path, contents: nil),
              let output = FileHandle(forWritingAtPath: tempURL.path) else {
            throw AdtsSegmentAppenderError.cannotOpenOutput
        }

        var written: UInt64 = 0
        do {
            for segment in segments {
                guard let input = FileHandle(forReadingAtPath: segment.path) else {
                    throw AdtsSegmentAppenderError.segmentUnreadable(segment)
                }
                defer { input.closeFile() }
                while true {
                    let chunk = autoreleasepool { input.readData(ofLength: 1 << 20) }
                    if chunk.isEmpty { break }
                    do {
                        try output.write(contentsOf: chunk)
                    } catch {
                        throw AdtsSegmentAppenderError.writeFailed(error.localizedDescription)
                    }
                    written += UInt64(chunk.count)
                }
            }
            output.closeFile()
        } catch {
            output.closeFile()
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
}
