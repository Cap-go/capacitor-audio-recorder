import AVFoundation
import Capacitor
import Foundation

@objc(CapacitorAudioRecorderPlugin)
public class CapacitorAudioRecorderPlugin: CAPPlugin, CAPBridgedPlugin, AVAudioRecorderDelegate {
    private let pluginVersion: String = "8.3.1"
    public let identifier = "CapacitorAudioRecorderPlugin"
    public let jsName = "CapacitorAudioRecorder"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "startRecording", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "pauseRecording", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "resumeRecording", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stopRecording", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "cancelRecording", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "resetAudioSessionForPlayback", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getRecordingStatus", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getCurrentAmplitude", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "checkPermissions", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "requestPermissions", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "removeAllListeners", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getPluginVersion", returnType: CAPPluginReturnPromise)
    ]

    private enum RecordingStatus: String {
        case inactive = "INACTIVE"
        case recording = "RECORDING"
        case paused = "PAUSED"
    }

    private let audioSession = AVAudioSession.sharedInstance()
    private var audioRecorder: AVAudioRecorder?
    private var currentFileURL: URL?
    private var completedSegmentURLs: [URL] = []
    private var recordingEncodingSettings: [String: Any]?
    private var interruptionSession = RecordingInterruptionSession()
    private var status: RecordingStatus = .inactive
    private var recordingStartUptime: TimeInterval?
    private var pauseStartUptime: TimeInterval?
    private var accumulatedPauseDuration: TimeInterval = 0
    private var shouldEmitStoppedEvent = true
    private var resetToPlaybackOnStop = false
    // AVAudioSession interruption observer. Active for the lifetime of a
    // recording so phone calls / Siri / alarms can pause cleanly without
    // losing the partially-recorded file.
    private var interruptionObserver: NSObjectProtocol?

    // MARK: - Plugin methods

    @objc func startRecording(_ call: CAPPluginCall) {
        guard status == .inactive else {
            call.reject("A recording is already in progress.")
            return
        }

        ensurePermission { granted in
            if !granted {
                call.reject("Microphone permission not granted.")
                return
            }

            do {
                try self.configureAudioSession(options: call)
                try self.beginRecording(call)
                call.resolve()
            } catch {
                self.resetRecorder(deleteFile: true)
                call.reject("Failed to start recording.", nil, error)
            }
        }
    }

    @objc func pauseRecording(_ call: CAPPluginCall) {
        guard let recorder = audioRecorder, status == .recording else {
            call.reject("No active recording to pause.")
            return
        }

        recorder.pause()
        pauseStartUptime = monotonicUptime()
        interruptionSession.markManualPause()
        syncStatusFromInterruptionSession()
        notifyListeners("recordingPaused", data: [:])
        call.resolve()
    }

    @objc func resumeRecording(_ call: CAPPluginCall) {
        guard status == .paused else {
            call.reject("No paused recording to resume.")
            return
        }

        do {
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            CAPLog.print("CapacitorAudioRecorderPlugin", "Failed to reactivate audio session on resume: \(error.localizedDescription)")
            call.reject("Failed to reactivate audio session.", nil, error)
            return
        }

        if audioRecorder == nil {
            do {
                try startNewRecordingSegment()
            } catch {
                call.reject("Failed to start a new recording segment after interruption.", nil, error)
                return
            }
        }

        guard let recorder = audioRecorder else {
            call.reject("No paused recording to resume.")
            return
        }

        let didStart = recorder.record()
        if !didStart {
            CAPLog.print("CapacitorAudioRecorderPlugin", "AVAudioRecorder.record() returned false on resume")
            call.reject("Failed to resume recording.")
            return
        }
        if let pauseStartUptime {
            accumulatedPauseDuration += monotonicUptime() - pauseStartUptime
        }
        interruptionSession.markManualResume()
        syncStatusFromInterruptionSession()
        pauseStartUptime = nil
        call.resolve()
    }

    @objc func stopRecording(_ call: CAPPluginCall) {
        guard status != .inactive else {
            call.reject("No active recording to stop.")
            return
        }

        if let recorder = audioRecorder {
            shouldEmitStoppedEvent = false
            recorder.stop()
        }

        finalizeStoppedRecording(call: call)
    }

    @objc func resetAudioSessionForPlayback(_ call: CAPPluginCall) {
        guard status == .inactive else {
            call.reject("A recording is in progress; stop or cancel it before resetting the audio session.")
            return
        }

        do {
            try applyPlaybackAudioSessionCategory()
            try audioSession.setActive(true)
            call.resolve()
        } catch {
            call.reject("Failed to reset audio session for playback.", nil, error)
        }
    }

    @objc func cancelRecording(_ call: CAPPluginCall) {
        guard audioRecorder != nil else {
            if !allSegmentURLs().isEmpty {
                do {
                    try deactivateSessionIfNeeded()
                } catch {
                    call.reject("Failed to reset audio session for playback.", nil, error)
                    return
                }
            }
            resetRecorder(deleteFile: true)
            call.resolve()
            return
        }

        shouldEmitStoppedEvent = false
        audioRecorder?.stop()
        do {
            try deactivateSessionIfNeeded()
        } catch {
            resetRecorder(deleteFile: true)
            call.reject("Failed to reset audio session for playback.", nil, error)
            return
        }
        resetRecorder(deleteFile: true)
        call.resolve()
    }

    @objc func getRecordingStatus(_ call: CAPPluginCall) {
        call.resolve(["status": status.rawValue])
    }

    @objc func getCurrentAmplitude(_ call: CAPPluginCall) {
        guard let recorder = audioRecorder, status == .recording else {
            call.resolve(["value": 0.0])
            return
        }
        recorder.updateMeters()
        let averagePowerDb = Double(recorder.averagePower(forChannel: 0))
        let linear: Double = averagePowerDb.isFinite ? pow(10.0, averagePowerDb / 20.0) : 0.0
        let value = max(0.0, min(1.0, linear))
        call.resolve(["value": value])
    }

    @objc override public func checkPermissions(_ call: CAPPluginCall) {
        call.resolve(["recordAudio": microphonePermissionState()])
    }

    @objc override public func requestPermissions(_ call: CAPPluginCall) {
        ensurePermission { granted in
            call.resolve(["recordAudio": granted ? "granted" : "denied"])
        }
    }

    @objc override public func removeAllListeners(_ call: CAPPluginCall) {
        super.removeAllListeners(call)
    }

    // MARK: - AVAudioRecorderDelegate

    public func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        resetRecorder(deleteFile: true)
        let message = error?.localizedDescription ?? "Unknown encoding error."
        notifyListeners("recordingError", data: ["message": message])
    }

    public func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let stopRequestedByPlugin = !shouldEmitStoppedEvent
        let outcome = interruptionSession.handleRecorderDidFinish(
            successfully: flag,
            stopRequestedByPlugin: stopRequestedByPlugin,
            activeSegmentIDAtFinish: currentFileURL?.lastPathComponent
        )

        switch outcome {
        case .ignoreBecauseStopWasRequested:
            return
        case .preserveSegmentAndStayPaused:
            archiveCurrentSegmentFromSession()
            audioRecorder = nil
            syncStatusFromInterruptionSession()
        case .failedPreservePartial:
            archiveCurrentSegmentFromSession()
            audioRecorder = nil
            syncStatusFromInterruptionSession()
            let uri = completedSegmentURLs.last?.absoluteString ?? currentFileURL?.absoluteString ?? ""
            notifyListeners("recordingError", data: [
                "message": "Recording finished unsuccessfully.",
                "uri": uri
            ])
        }
    }

    // MARK: - Helpers

    private func configureAudioSession(options call: CAPPluginCall) throws {
        var categoryOptions: AVAudioSession.CategoryOptions = []
        if let options = call.getArray("audioSessionCategoryOptions", String.self) {
            options.forEach {
                if let option = mapCategoryOption(from: $0) {
                    categoryOptions.insert(option)
                }
            }
        } else {
            categoryOptions.insert(.duckOthers)
        }

        let mode = mapSessionMode(from: call.getString("audioSessionMode")) ?? .measurement

        resetToPlaybackOnStop = call.getBool("resetToPlaybackOnStop") ?? false

        try audioSession.setCategory(.playAndRecord, mode: mode, options: categoryOptions.union([.allowBluetooth, .defaultToSpeaker]))
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func beginRecording(_ call: CAPPluginCall) throws {
        let bitRate = call.getDouble("bitRate") ?? 192_000
        let sampleRate = call.getDouble("sampleRate") ?? 44_100

        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent("CapacitorAudioRecorder", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directoryURL.path) {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        let fileURL = directoryURL.appendingPathComponent("\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: bitRate,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        recorder.delegate = self
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()
        recorder.record()

        audioRecorder = recorder
        currentFileURL = fileURL
        completedSegmentURLs = []
        recordingEncodingSettings = settings
        interruptionSession.markRecordingStarted(segmentID: fileURL.lastPathComponent)
        syncStatusFromInterruptionSession()
        recordingStartUptime = monotonicUptime()
        accumulatedPauseDuration = 0
        pauseStartUptime = nil
        shouldEmitStoppedEvent = true

        registerInterruptionObserver()
    }

    private func registerInterruptionObserver() {
        unregisterInterruptionObserver()
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: audioSession,
            queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification: notification)
        }
    }

    private func unregisterInterruptionObserver() {
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionObserver = nil
        }
    }

    private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            guard let recorder = audioRecorder, interruptionSession.handleInterruptionBegan() else { return }
            recorder.pause()
            pauseStartUptime = monotonicUptime()
            syncStatusFromInterruptionSession()
            notifyListeners("recordingInterruptionBegan", data: [:])

        case .ended:
            guard status == .paused else {
                notifyListeners("recordingInterruptionEnded", data: ["shouldResume": false])
                return
            }

            let shouldResumeHint: Bool = {
                guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else {
                    return false
                }
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                return options.contains(.shouldResume)
            }()

            let plan = interruptionSession.handleInterruptionEnded(shouldResumeHint: shouldResumeHint)
            guard plan.shouldAttemptAutoResume, let recorder = audioRecorder else {
                notifyListeners("recordingInterruptionEnded", data: ["shouldResume": false])
                return
            }

            var didResumeRecording = false
            do {
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
                let didStart = recorder.record()
                if didStart {
                    if let pauseStart = pauseStartUptime {
                        accumulatedPauseDuration += monotonicUptime() - pauseStart
                    }
                    interruptionSession.markAutoResumeSucceeded()
                    syncStatusFromInterruptionSession()
                    pauseStartUptime = nil
                    didResumeRecording = true
                } else {
                    CAPLog.print("CapacitorAudioRecorderPlugin", "AVAudioRecorder.record() returned false after interruption")
                }
            } catch {
                CAPLog.print("CapacitorAudioRecorderPlugin", "Failed to resume after interruption: \(error.localizedDescription)")
            }
            notifyListeners("recordingInterruptionEnded", data: ["shouldResume": didResumeRecording])

        @unknown default:
            return
        }
    }

    private func monotonicUptime() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    /// Elapsed recording time in milliseconds from monotonic start/pause tracking (Android-aligned).
    private func recordingDurationMilliseconds() -> Double {
        guard let start = recordingStartUptime else {
            return 0
        }
        var pauseTotal = accumulatedPauseDuration
        if let pauseStart = pauseStartUptime {
            pauseTotal += monotonicUptime() - pauseStart
        }
        let seconds = monotonicUptime() - start - pauseTotal
        return max(0, seconds) * 1000
    }

    private func resetRecorder(deleteFile: Bool) {
        unregisterInterruptionObserver()
        if deleteFile {
            deleteRecordingFiles(at: allSegmentURLs())
        }
        audioRecorder = nil
        currentFileURL = nil
        completedSegmentURLs = []
        recordingEncodingSettings = nil
        interruptionSession.resetToInactive()
        syncStatusFromInterruptionSession()
        recordingStartUptime = nil
        pauseStartUptime = nil
        accumulatedPauseDuration = 0
    }

    private func syncStatusFromInterruptionSession() {
        status = RecordingStatus(rawValue: interruptionSession.status.rawValue) ?? .inactive
    }

    private func archiveCurrentSegmentFromSession() {
        if let url = currentFileURL {
            completedSegmentURLs.append(url)
        }
        currentFileURL = nil
    }

    private func allSegmentURLs() -> [URL] {
        var urls = completedSegmentURLs
        if let currentFileURL {
            urls.append(currentFileURL)
        }
        return urls
    }

    private func recordingDirectoryURL() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent("CapacitorAudioRecorder", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directoryURL.path) {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        return directoryURL
    }

    private func startNewRecordingSegment() throws {
        guard let settings = recordingEncodingSettings else {
            throw NSError(domain: "CapacitorAudioRecorderPlugin", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Missing recording settings for a new segment."
            ])
        }

        let directoryURL = try recordingDirectoryURL()
        let fileURL = directoryURL.appendingPathComponent("\(UUID().uuidString).m4a")
        let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        recorder.delegate = self
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()

        audioRecorder = recorder
        currentFileURL = fileURL
        interruptionSession.markNewSegmentStarted(segmentID: fileURL.lastPathComponent)
        syncStatusFromInterruptionSession()
        shouldEmitStoppedEvent = true
    }

    private func finalizeStoppedRecording(call: CAPPluginCall) {
        let segments = allSegmentURLs()
        guard !segments.isEmpty else {
            call.reject("No active recording to stop.")
            return
        }

        do {
            try deactivateSessionIfNeeded()
        } catch {
            call.reject("Failed to reset audio session for playback.", nil, error)
            return
        }

        do {
            let (outputURL, durationMilliseconds) = try produceFinalRecording(from: segments)
            let result: [String: Any] = [
                "duration": durationMilliseconds,
                "uri": outputURL.absoluteString
            ]
            notifyListeners("recordingStopped", data: result)
            call.resolve(result)
            resetRecorder(deleteFile: false)
        } catch {
            call.reject("Failed to finalize recording.", nil, error)
        }
    }

    private func produceFinalRecording(from segments: [URL]) throws -> (URL, Double) {
        if segments.count == 1 {
            let url = segments[0]
            let duration = AudioSegmentMerger.durationMilliseconds(for: url)
            return (url, duration)
        }

        let directoryURL = try recordingDirectoryURL()
        let mergedURL = directoryURL.appendingPathComponent("\(UUID().uuidString).m4a")
        let duration = try AudioSegmentMerger.mergeSegments(segments, into: mergedURL)
        deleteRecordingFiles(at: segments)
        return (mergedURL, duration)
    }

    private func deleteRecordingFiles(at urls: [URL]) {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func applyPlaybackAudioSessionCategory() throws {
        try audioSession.setCategory(.playback, mode: .default, options: [])
    }

    private func deactivateSessionIfNeeded() throws {
        var playbackResetError: Error?
        if resetToPlaybackOnStop {
            do {
                try applyPlaybackAudioSessionCategory()
                resetToPlaybackOnStop = false
            } catch {
                playbackResetError = error
                CAPLog.print("CapacitorAudioRecorderPlugin", "Failed to set playback audio session category: \(error.localizedDescription)")
            }
        }
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            CAPLog.print("CapacitorAudioRecorderPlugin", "Failed to deactivate audio session: \(error.localizedDescription)")
        }
        if let playbackResetError {
            throw playbackResetError
        }
    }

    private func ensurePermission(completion: @escaping (Bool) -> Void) {
        switch audioSession.recordPermission {
        case .granted:
            completion(true)
        case .denied:
            completion(false)
        case .undetermined:
            audioSession.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        @unknown default:
            completion(false)
        }
    }

    private func microphonePermissionState() -> String {
        switch audioSession.recordPermission {
        case .granted:
            return "granted"
        case .denied:
            return "denied"
        case .undetermined:
            return "prompt"
        @unknown default:
            return "prompt"
        }
    }

    private func mapCategoryOption(from value: String) -> AVAudioSession.CategoryOptions? {
        switch value.uppercased() {
        case "ALLOW_AIR_PLAY":
            return .allowAirPlay
        case "ALLOW_BLUETOOTH":
            return .allowBluetooth
        case "ALLOW_BLUETOOTH_A2DP":
            return .allowBluetoothA2DP
        case "DEFAULT_TO_SPEAKER":
            return .defaultToSpeaker
        case "DUCK_OTHERS":
            return .duckOthers
        case "INTERRUPT_SPOKEN_AUDIO_AND_MIX_WITH_OTHERS":
            return .interruptSpokenAudioAndMixWithOthers
        case "MIX_WITH_OTHERS":
            return .mixWithOthers
        case "OVERRIDE_MUTED_MICROPHONE_INTERRUPTION":
            return .overrideMutedMicrophoneInterruption
        default:
            return nil
        }
    }

    private func mapSessionMode(from value: String?) -> AVAudioSession.Mode? {
        guard let value else { return nil }
        switch value.uppercased() {
        case "GAME_CHAT":
            return .gameChat
        case "MEASUREMENT":
            return .measurement
        case "SPOKEN_AUDIO":
            return .spokenAudio
        case "VIDEO_CHAT":
            return .videoChat
        case "VIDEO_RECORDING":
            return .videoRecording
        case "VOICE_CHAT":
            return .voiceChat
        default:
            return .default
        }
    }

    @objc func getPluginVersion(_ call: CAPPluginCall) {
        call.resolve(["version": self.pluginVersion])
    }
}
