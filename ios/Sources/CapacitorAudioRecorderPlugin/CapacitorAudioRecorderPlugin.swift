import AVFoundation
import Capacitor
import Foundation

@objc(CapacitorAudioRecorderPlugin)
public class CapacitorAudioRecorderPlugin: CAPPlugin, CAPBridgedPlugin, AVAudioRecorderDelegate {
    private let pluginVersion: String = "8.2.1"
    public let identifier = "CapacitorAudioRecorderPlugin"
    public let jsName = "CapacitorAudioRecorder"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "startRecording", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "pauseRecording", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "resumeRecording", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stopRecording", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "cancelRecording", returnType: CAPPluginReturnPromise),
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
    private var status: RecordingStatus = .inactive
    private var recordingStartDate: Date?
    private var pauseStartDate: Date?
    private var accumulatedPauseDuration: TimeInterval = 0
    private var shouldEmitStoppedEvent = true
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
        pauseStartDate = Date()
        status = .paused
        notifyListeners("recordingPaused", data: [:])
        call.resolve()
    }

    @objc func resumeRecording(_ call: CAPPluginCall) {
        guard let recorder = audioRecorder, status == .paused else {
            call.reject("No paused recording to resume.")
            return
        }

        // Re-activate the AVAudioSession before calling record(). After an
        // iOS interruption (Siri / call / alarm), the session is deactivated
        // and won't auto-reactivate when the user taps resume. Without this,
        // record() silently returns false, no audio is captured, and the
        // recorder eventually fires audioRecorderDidFinishRecording(false)
        // which destroys the file via resetRecorder(deleteFile: true).
        do {
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            CAPLog.print("CapacitorAudioRecorderPlugin", "Failed to reactivate audio session on resume: \(error.localizedDescription)")
            call.reject("Failed to reactivate audio session.", nil, error)
            return
        }

        if let pauseStartDate {
            accumulatedPauseDuration += Date().timeIntervalSince(pauseStartDate)
        }
        let didStart = recorder.record()
        if !didStart {
            CAPLog.print("CapacitorAudioRecorderPlugin", "AVAudioRecorder.record() returned false on resume")
            call.reject("Failed to resume recording.")
            return
        }
        status = .recording
        pauseStartDate = nil
        call.resolve()
    }

    @objc func stopRecording(_ call: CAPPluginCall) {
        // Recovery path: an interruption-driven recorder failure may have
        // already torn down the AVAudioRecorder via the delegate callback,
        // but the partial file is preserved on disk. Return that file so
        // the caller can finalize what was captured before the failure
        // instead of getting "no active recording" + losing everything.
        if audioRecorder == nil, let url = currentFileURL {
            let result: [String: Any] = [
                "duration": 0,
                "uri": url.absoluteString
            ]
            currentFileURL = nil
            unregisterInterruptionObserver()
            notifyListeners("recordingStopped", data: result)
            call.resolve(result)
            return
        }

        guard let recorder = audioRecorder, status != .inactive else {
            call.reject("No active recording to stop.")
            return
        }

        shouldEmitStoppedEvent = false
        recorder.stop()
        deactivateSessionIfNeeded()

        let durationMilliseconds = recorder.currentTime * 1000
        let uri = currentFileURL?.absoluteString ?? ""

        let result: [String: Any] = [
            "duration": durationMilliseconds,
            "uri": uri
        ]

        notifyListeners("recordingStopped", data: result)
        call.resolve(result)
        resetRecorder(deleteFile: false)
    }

    @objc func cancelRecording(_ call: CAPPluginCall) {
        guard audioRecorder != nil else {
            resetRecorder(deleteFile: true)
            call.resolve()
            return
        }

        shouldEmitStoppedEvent = false
        audioRecorder?.stop()
        deactivateSessionIfNeeded()
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
        guard shouldEmitStoppedEvent else {
            return
        }

        if flag {
            let durationMilliseconds = recorder.currentTime * 1000
            let uri = currentFileURL?.absoluteString ?? ""
            let result: [String: Any] = [
                "duration": durationMilliseconds,
                "uri": uri
            ]
            notifyListeners("recordingStopped", data: result)
            resetRecorder(deleteFile: false)
        } else {
            // Recording terminated unexpectedly (most often: an audio session
            // interruption + a record() call that didn't actually resume).
            // Preserve the partial file on disk and KEEP currentFileURL alive
            // so a subsequent stopRecording call can recover what was captured
            // before the failure. Reset everything else so the plugin's state
            // doesn't lie about an active recording.
            let uri = currentFileURL?.absoluteString ?? ""
            notifyListeners("recordingError", data: [
                "message": "Recording finished unsuccessfully.",
                "uri": uri
            ])
            unregisterInterruptionObserver()
            self.audioRecorder = nil
            // intentionally NOT clearing currentFileURL — it's the recovery breadcrumb
            status = .inactive
            recordingStartDate = nil
            pauseStartDate = nil
            accumulatedPauseDuration = 0
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
        status = .recording
        recordingStartDate = Date()
        accumulatedPauseDuration = 0
        pauseStartDate = nil
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
            // iOS is interrupting (call, Siri, alarm, Bluetooth disconnect).
            // Pause the recorder synchronously inside the notification handler
            // so AVAudioRecorder finalizes pending writes before the session
            // is deactivated. Without this, the recorder hits
            // audioRecorderDidFinishRecording(success: false) and the file
            // is destroyed.
            guard let recorder = audioRecorder, status == .recording else { return }
            recorder.pause()
            pauseStartDate = Date()
            status = .paused
            notifyListeners("recordingInterruptionBegan", data: [:])

        case .ended:
            // Interruption ended. iOS hints whether we should resume via the
            // shouldResume option. If yes, re-activate the session and record;
            // if no, stay paused and let the user resume manually.
            guard let recorder = audioRecorder, status == .paused else {
                notifyListeners("recordingInterruptionEnded", data: ["shouldResume": false])
                return
            }
            let shouldResume: Bool = {
                guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else {
                    return false
                }
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                return options.contains(.shouldResume)
            }()

            if shouldResume {
                do {
                    try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
                    if let pauseStart = pauseStartDate {
                        accumulatedPauseDuration += Date().timeIntervalSince(pauseStart)
                    }
                    recorder.record()
                    status = .recording
                    pauseStartDate = nil
                } catch {
                    CAPLog.print("CapacitorAudioRecorderPlugin", "Failed to resume after interruption: \(error.localizedDescription)")
                }
            }
            notifyListeners("recordingInterruptionEnded", data: ["shouldResume": shouldResume])

        @unknown default:
            return
        }
    }

    private func resetRecorder(deleteFile: Bool) {
        unregisterInterruptionObserver()
        if deleteFile, let url = currentFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        audioRecorder = nil
        currentFileURL = nil
        status = .inactive
        recordingStartDate = nil
        pauseStartDate = nil
        accumulatedPauseDuration = 0
    }

    private func deactivateSessionIfNeeded() {
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            CAPLog.print("CapacitorAudioRecorderPlugin", "Failed to deactivate audio session: \(error.localizedDescription)")
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
