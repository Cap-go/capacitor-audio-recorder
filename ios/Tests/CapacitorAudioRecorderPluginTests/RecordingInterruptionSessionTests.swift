import XCTest
@testable import CapacitorAudioRecorderPlugin

final class RecordingInterruptionSessionTests: XCTestCase {
    /// Simulates: record -> incoming call (interruption began) -> call ends with
    /// shouldResume -> plugin auto-resumes -> ~20 ms later the system finalizes the
    /// recorder with successfully == true (8.2.9 bug).
    func testInterruptionAutoResumeThenSystemFinish_preservesAudioAndPausedState() {
        var session = RecordingInterruptionSession()
        session.markRecordingStarted(segmentID: "segment-1.m4a")

        XCTAssertTrue(session.handleInterruptionBegan())
        XCTAssertEqual(session.status, .paused)

        let ended = session.handleInterruptionEnded(shouldResumeHint: true)
        XCTAssertTrue(ended.shouldAttemptAutoResume)
        session.markAutoResumeSucceeded()
        XCTAssertEqual(session.status, .recording)

        let outcome = session.handleRecorderDidFinish(
            successfully: true,
            stopRequestedByPlugin: false,
            activeSegmentIDAtFinish: "segment-1.m4a"
        )

        XCTAssertEqual(outcome, .preserveSegmentAndStayPaused)
        XCTAssertEqual(session.status, .paused)
        XCTAssertEqual(session.completedSegmentIDs, ["segment-1.m4a"])
        XCTAssertNil(session.activeSegmentID)
        XCTAssertFalse(session.hasActiveRecorder)
        XCTAssertTrue(session.canResumeRecording)
        XCTAssertTrue(session.canStopRecording)
    }

    func testInterruptionBeganThenEndedWithoutResumeHint_staysPaused() {
        var session = RecordingInterruptionSession()
        session.markRecordingStarted(segmentID: "segment-1.m4a")
        XCTAssertTrue(session.handleInterruptionBegan())

        let ended = session.handleInterruptionEnded(shouldResumeHint: false)
        XCTAssertFalse(ended.shouldAttemptAutoResume)
        XCTAssertEqual(session.status, .paused)
        XCTAssertTrue(session.canResumeRecording)
    }

    func testSystemFinishThenResumeThenStop_accumulatesSegments() {
        var session = RecordingInterruptionSession()
        session.markRecordingStarted(segmentID: "segment-1.m4a")
        XCTAssertTrue(session.handleInterruptionBegan())

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
}
