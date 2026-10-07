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
        guard segmentURLs.count > 1 else {
            if let only = segmentURLs.first {
                return durationMilliseconds(for: only)
            }
            return 0
        }

        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw AudioSegmentMergerError.unableToCreateCompositionTrack
        }

        var insertTime = CMTime.zero
        for url in segmentURLs {
            let asset = AVURLAsset(url: url)
            guard let sourceTrack = asset.tracks(withMediaType: .audio).first else {
                throw AudioSegmentMergerError.noAudioInSegment(url)
            }
            let duration = asset.duration
            try compositionTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: sourceTrack,
                at: insertTime
            )
            insertTime = CMTimeAdd(insertTime, duration)
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
        urls.reduce(0) { $0 + durationMilliseconds(for: $1) }
    }
}
