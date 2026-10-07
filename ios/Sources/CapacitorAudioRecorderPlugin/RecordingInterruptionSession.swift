import Foundation

/// Testable state for iOS recording across AVAudioSession interruptions and
/// unexpected `audioRecorderDidFinishRecording` callbacks.
struct RecordingInterruptionSession {
    enum Status: String, Equatable {
        case inactive = "INACTIVE"
        case recording = "RECORDING"
        case paused = "PAUSED"
    }

    enum RecorderFinishOutcome: Equatable {
        case ignoreBecauseStopWasRequested
        case preserveSegmentAndStayPaused
        case failedPreservePartial
    }

    private(set) var status: Status = .inactive
    private(set) var completedSegmentIDs: [String] = []
    var activeSegmentID: String?
    private(set) var hasActiveRecorder: Bool = false

    var canResumeRecording: Bool {
        status == .paused && (!completedSegmentIDs.isEmpty || activeSegmentID != nil)
    }

    var canStopRecording: Bool {
        status == .recording || status == .paused
    }

    mutating func markRecordingStarted(segmentID: String) {
        status = .recording
        activeSegmentID = segmentID
        hasActiveRecorder = true
        completedSegmentIDs = []
    }

    mutating func handleInterruptionBegan() -> Bool {
        guard hasActiveRecorder, status == .recording else {
            return false
        }
        status = .paused
        return true
    }

    struct InterruptionEndedResult {
        let shouldAttemptAutoResume: Bool
        let reportedShouldResume: Bool
    }

    mutating func handleInterruptionEnded(shouldResumeHint: Bool) -> InterruptionEndedResult {
        guard status == .paused, hasActiveRecorder else {
            return InterruptionEndedResult(shouldAttemptAutoResume: false, reportedShouldResume: false)
        }
        guard shouldResumeHint else {
            return InterruptionEndedResult(shouldAttemptAutoResume: false, reportedShouldResume: false)
        }
        return InterruptionEndedResult(shouldAttemptAutoResume: true, reportedShouldResume: false)
    }

    mutating func markAutoResumeSucceeded() {
        guard status == .paused, hasActiveRecorder else {
            return
        }
        status = .recording
    }

    mutating func handleRecorderDidFinish(
        successfully: Bool,
        stopRequestedByPlugin: Bool,
        activeSegmentIDAtFinish: String?
    ) -> RecorderFinishOutcome {
        if stopRequestedByPlugin {
            return .ignoreBecauseStopWasRequested
        }

        if successfully {
            return applySuccessfulSystemFinish(activeSegmentIDAtFinish: activeSegmentIDAtFinish)
        }

        archiveActiveSegment(activeSegmentIDAtFinish: activeSegmentIDAtFinish)
        hasActiveRecorder = false
        status = .paused
        return .failedPreservePartial
    }

    mutating func markNewSegmentStarted(segmentID: String) {
        activeSegmentID = segmentID
        hasActiveRecorder = true
        status = .recording
    }

    mutating func markManualPause() {
        guard status == .recording else {
            return
        }
        status = .paused
    }

    mutating func markManualResume() {
        guard status == .paused else {
            return
        }
        status = .recording
    }

    mutating func resetToInactive() {
        status = .inactive
        completedSegmentIDs = []
        activeSegmentID = nil
        hasActiveRecorder = false
    }

    // MARK: - Private

    private mutating func applySuccessfulSystemFinish(activeSegmentIDAtFinish: String?) -> RecorderFinishOutcome {
        archiveActiveSegment(activeSegmentIDAtFinish: activeSegmentIDAtFinish)
        hasActiveRecorder = false
        status = .paused
        return .preserveSegmentAndStayPaused
    }

    private mutating func archiveActiveSegment(activeSegmentIDAtFinish: String?) {
        guard let segmentID = activeSegmentIDAtFinish else {
            return
        }
        completedSegmentIDs.append(segmentID)
        activeSegmentID = nil
    }
}
