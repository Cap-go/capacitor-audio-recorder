import AVFoundation
import Foundation

enum AudioSegmentMergerError: Error {
    case unableToCreateCompositionTrack
    case noAudioInSegment(URL)
    case exportSessionUnavailable
    case exportFailed(String?)
}

enum AudioSegmentMerger {
    static func mergeSegments(_ segmentURLs: [URL], into outputURL: URL) throws -> Double {
        let usable = usableSegments(from: segmentURLs)
        guard !usable.isEmpty else {
            throw AudioSegmentMergerError.noAudioInSegment(segmentURLs.first ?? outputURL)
        }
        guard usable.count > 1 else {
            return durationMilliseconds(for: usable[0])
        }

        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw AudioSegmentMergerError.unableToCreateCompositionTrack
        }

        var insertTime = CMTime.zero
        var insertedCount = 0
        for url in usable {
            let asset = AVURLAsset(url: url)
            let duration = asset.duration
            guard let sourceTrack = asset.tracks(withMediaType: .audio).first,
                  duration.isNumeric, CMTimeGetSeconds(duration) > 0 else {
                continue
            }
            try compositionTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: sourceTrack,
                at: insertTime
            )
            insertTime = CMTimeAdd(insertTime, duration)
            insertedCount += 1
        }

        guard insertedCount > 0 else {
            throw AudioSegmentMergerError.noAudioInSegment(usable[0])
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw AudioSegmentMergerError.exportSessionUnavailable
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a

        let semaphore = DispatchSemaphore(value: 0)
        exportSession.exportAsynchronously {
            semaphore.signal()
        }
        semaphore.wait()

        if exportSession.status != .completed {
            throw AudioSegmentMergerError.exportFailed(exportSession.error?.localizedDescription)
        }

        return CMTimeGetSeconds(insertTime) * 1000
    }

    static func durationMilliseconds(for url: URL) -> Double {
        let asset = AVURLAsset(url: url)
        let seconds = CMTimeGetSeconds(asset.duration)
        guard seconds.isFinite, seconds > 0 else {
            return 0
        }
        return seconds * 1000
    }

    static func totalDurationMilliseconds(for urls: [URL]) -> Double {
        usableSegments(from: urls).reduce(0) { $0 + durationMilliseconds(for: $1) }
    }

    /// Picks the segment with the longest measured duration, falling back to largest file size.
    static func preferredFallbackSegment(from segmentURLs: [URL]) -> URL? {
        let candidates = usableSegments(from: segmentURLs)
        if candidates.isEmpty {
            return segmentURLs.max(by: { fileByteCount($0) < fileByteCount($1) })
        }
        return candidates.max(by: { durationMilliseconds(for: $0) < durationMilliseconds(for: $1) })
    }

    static func usableSegments(from segmentURLs: [URL]) -> [URL] {
        segmentURLs.filter { url in
            let asset = AVURLAsset(url: url)
            guard asset.tracks(withMediaType: .audio).first != nil else {
                return false
            }
            let seconds = CMTimeGetSeconds(asset.duration)
            return seconds.isFinite && seconds > 0
        }
    }

    private static func fileByteCount(_ url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }
}
