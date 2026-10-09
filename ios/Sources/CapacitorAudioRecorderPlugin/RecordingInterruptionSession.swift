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
        case preserveSegmentAndContinueAutoResume
    }

    enum InterruptionBeganOutcome: Equatable {
        case pausedActiveRecorder
        case archivedBecauseRecorderAlreadyStopped
        case ignored
    }

    private(set) var status: Status = .inactive
    private(set) var completedSegmentIDs: [String] = []
    var activeSegmentID: String?
    private(set) var hasActiveRecorder: Bool = false
    private(set) var pausedByInterruption: Bool = false

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
        pausedByInterruption = false
    }

    mutating func handleInterruptionBegan(recorderIsRecording: Bool) -> InterruptionBeganOutcome {
        guard hasActiveRecorder, status == .recording else {
            return .ignored
        }
        pausedByInterruption = true
        status = .paused
        if recorderIsRecording {
            return .pausedActiveRecorder
        }
        archiveActiveSegment(activeSegmentIDAtFinish: activeSegmentID)
        hasActiveRecorder = false
        return .archivedBecauseRecorderAlreadyStopped
    }

    struct InterruptionEndedResult {
        let shouldAttemptAutoResume: Bool
        let reportedShouldResume: Bool
    }

    mutating func handleInterruptionEnded(shouldResumeHint: Bool) -> InterruptionEndedResult {
        guard status == .paused, pausedByInterruption else {
            return InterruptionEndedResult(shouldAttemptAutoResume: false, reportedShouldResume: false)
        }
        guard shouldResumeHint else {
            return InterruptionEndedResult(shouldAttemptAutoResume: false, reportedShouldResume: false)
        }
        return InterruptionEndedResult(shouldAttemptAutoResume: true, reportedShouldResume: false)
    }

    mutating func markAutoResumeSucceeded() {
        guard status == .paused else {
            return
        }
        status = .recording
        pausedByInterruption = false
    }

    mutating func handleRecorderDidFinish(
        successfully: Bool,
        stopRequestedByPlugin: Bool,
        activeSegmentIDAtFinish: String?,
        continuingWithAutoResume: Bool = false
    ) -> RecorderFinishOutcome {
        if stopRequestedByPlugin {
            return .ignoreBecauseStopWasRequested
        }

        if successfully {
            let outcome = applySuccessfulSystemFinish(activeSegmentIDAtFinish: activeSegmentIDAtFinish)
            if continuingWithAutoResume {
                return .preserveSegmentAndContinueAutoResume
            }
            return outcome
        }

        archiveActiveSegment(activeSegmentIDAtFinish: activeSegmentIDAtFinish)
        hasActiveRecorder = false
        status = .paused
        return .failedPreservePartial
    }

    mutating func markNewSegmentStarted(segmentID: String) {
        activeSegmentID = segmentID
        hasActiveRecorder = true
        pausedByInterruption = false
    }

    mutating func markManualPause() {
        guard status == .recording else {
            return
        }
        status = .paused
        pausedByInterruption = false
    }

    mutating func markManualResume() {
        guard status == .paused else {
            return
        }
        status = .recording
        pausedByInterruption = false
    }

    mutating func markRecorderReleasedWithoutFinish() {
        hasActiveRecorder = false
    }

    mutating func resetToInactive() {
        status = .inactive
        completedSegmentIDs = []
        activeSegmentID = nil
        hasActiveRecorder = false
        pausedByInterruption = false
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
