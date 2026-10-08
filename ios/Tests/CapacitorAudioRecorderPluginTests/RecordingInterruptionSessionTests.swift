import XCTest
@testable import CapacitorAudioRecorderPlugin

final class RecordingInterruptionSessionTests: XCTestCase {
    /// Simulates: record -> incoming call -> auto-resume stops segment 1, archives it,
    /// then starts segment 2 on a new file.
    func testInterruptionAutoResumeThenSystemFinish_preservesAudioAndPausedState() {
        var session = RecordingInterruptionSession()
        session.markRecordingStarted(segmentID: "segment-1.m4a")

        XCTAssertEqual(session.handleInterruptionBegan(recorderIsRecording: true), .pausedActiveRecorder)
        XCTAssertEqual(session.status, .paused)
        XCTAssertTrue(session.pausedByInterruption)

        let ended = session.handleInterruptionEnded(shouldResumeHint: true)
        XCTAssertTrue(ended.shouldAttemptAutoResume)

        let outcome = session.handleRecorderDidFinish(
            successfully: true,
            stopRequestedByPlugin: false,
            activeSegmentIDAtFinish: "segment-1.m4a",
            continuingWithAutoResume: true
        )
        XCTAssertEqual(outcome, .preserveSegmentAndContinueAutoResume)
        XCTAssertEqual(session.completedSegmentIDs, ["segment-1.m4a"])
        XCTAssertNil(session.activeSegmentID)
        XCTAssertFalse(session.hasActiveRecorder)
        XCTAssertEqual(session.status, .paused)

        session.markNewSegmentStarted(segmentID: "segment-2.m4a")
        session.markAutoResumeSucceeded()
        XCTAssertEqual(session.status, .recording)
        XCTAssertEqual(session.activeSegmentID, "segment-2.m4a")
        XCTAssertTrue(session.hasActiveRecorder)
        XCTAssertTrue(session.canResumeRecording)
        XCTAssertTrue(session.canStopRecording)
    }

    func testInterruptionBeganThenEndedWithoutResumeHint_staysPaused() {
        var session = RecordingInterruptionSession()
        session.markRecordingStarted(segmentID: "segment-1.m4a")
        XCTAssertEqual(session.handleInterruptionBegan(recorderIsRecording: true), .pausedActiveRecorder)

        let ended = session.handleInterruptionEnded(shouldResumeHint: false)
        XCTAssertFalse(ended.shouldAttemptAutoResume)
        XCTAssertEqual(session.status, .paused)
        XCTAssertTrue(session.canResumeRecording)
    }

    /// iOS already stopped the recorder when the interruption began (isRecording == false).
    func testInterruptionBeganWhenRecorderAlreadyStopped_archivesSegmentImmediately() {
        var session = RecordingInterruptionSession()
        session.markRecordingStarted(segmentID: "segment-1.m4a")

        let began = session.handleInterruptionBegan(recorderIsRecording: false)
        XCTAssertEqual(began, .archivedBecauseRecorderAlreadyStopped)
        XCTAssertEqual(session.status, .paused)
        XCTAssertEqual(session.completedSegmentIDs, ["segment-1.m4a"])
        XCTAssertNil(session.activeSegmentID)
        XCTAssertFalse(session.hasActiveRecorder)
        XCTAssertTrue(session.pausedByInterruption)

        let ended = session.handleInterruptionEnded(shouldResumeHint: true)
        XCTAssertTrue(ended.shouldAttemptAutoResume)

        session.markNewSegmentStarted(segmentID: "segment-2.m4a")
        XCTAssertEqual(session.completedSegmentIDs, ["segment-1.m4a"])
        XCTAssertEqual(session.activeSegmentID, "segment-2.m4a")
    }

    func testUserPausedRecording_doesNotAutoResumeAfterInterruptionEnds() {
        var session = RecordingInterruptionSession()
        session.markRecordingStarted(segmentID: "segment-1.m4a")
        session.markManualPause()
        XCTAssertFalse(session.pausedByInterruption)

        let ended = session.handleInterruptionEnded(shouldResumeHint: true)
        XCTAssertFalse(ended.shouldAttemptAutoResume)
        XCTAssertEqual(session.status, .paused)
    }

    func testSystemFinishThenResumeThenStop_accumulatesSegments() {
        var session = RecordingInterruptionSession()
        session.markRecordingStarted(segmentID: "segment-1.m4a")
        XCTAssertEqual(session.handleInterruptionBegan(recorderIsRecording: true), .pausedActiveRecorder)

        _ = session.handleRecorderDidFinish(
            successfully: true,
            stopRequestedByPlugin: false,
            activeSegmentIDAtFinish: "segment-1.m4a"
        )
        XCTAssertEqual(session.completedSegmentIDs, ["segment-1.m4a"])
        XCTAssertTrue(session.canResumeRecording)

        session.markNewSegmentStarted(segmentID: "segment-2.m4a")
        XCTAssertEqual(session.status, .recording)

        let stopOutcome = session.handleRecorderDidFinish(
            successfully: true,
            stopRequestedByPlugin: true,
            activeSegmentIDAtFinish: "segment-2.m4a"
        )
        XCTAssertEqual(stopOutcome, .ignoreBecauseStopWasRequested)
    }

    func testFinalizeSegmentForAutoResume_continuesWithNewSegment() {
        var session = RecordingInterruptionSession()
        session.markRecordingStarted(segmentID: "segment-1.m4a")
        XCTAssertEqual(session.handleInterruptionBegan(recorderIsRecording: true), .pausedActiveRecorder)

        let outcome = session.handleRecorderDidFinish(
            successfully: true,
            stopRequestedByPlugin: false,
            activeSegmentIDAtFinish: "segment-1.m4a",
            continuingWithAutoResume: true
        )
        XCTAssertEqual(outcome, .preserveSegmentAndContinueAutoResume)
        XCTAssertEqual(session.completedSegmentIDs, ["segment-1.m4a"])
        XCTAssertFalse(session.hasActiveRecorder)
    }

    func testEncodingFailurePreservesCompletedSegments() {
        var session = RecordingInterruptionSession()
        session.markRecordingStarted(segmentID: "segment-1.m4a")
        XCTAssertEqual(session.handleInterruptionBegan(recorderIsRecording: false), .archivedBecauseRecorderAlreadyStopped)
        session.markNewSegmentStarted(segmentID: "segment-2.m4a")

        let outcome = session.handleRecorderDidFinish(
            successfully: false,
            stopRequestedByPlugin: false,
            activeSegmentIDAtFinish: "segment-2.m4a"
        )
        XCTAssertEqual(outcome, .failedPreservePartial)
        XCTAssertEqual(session.completedSegmentIDs, ["segment-1.m4a", "segment-2.m4a"])
    }
}
