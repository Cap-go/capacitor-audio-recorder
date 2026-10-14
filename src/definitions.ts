import type { PluginListenerHandle } from '@capacitor/core';

/**
 * Result returned by {@link CapacitorAudioRecorderPlugin.getRecordingStatus}.
 *
 * @since 1.0.0
 */
export interface GetRecordingStatusResult {
  /**
   * The current recording status.
   *
   * @since 1.0.0
   */
  status: RecordingStatus;
}

/**
 * Result returned by {@link CapacitorAudioRecorderPlugin.getCurrentAmplitude}.
 *
 * @since 8.1.0
 */
export interface GetCurrentAmplitudeResult {
  /**
   * The current input amplitude normalized to the `[0, 1]` range, where `0`
   * represents silence and `1` represents the maximum level the platform can
   * report. The value is `0` when no recording is active.
   *
   * Note: the source signal differs between platforms — Android reports the
   * peak sample amplitude since the last call, iOS reports the average power
   * in dB converted to linear, and Web reports the RMS of the latest frame.
   * Consumers that need cross-platform parity may want to apply a
   * per-platform scaling curve.
   *
   * @since 8.1.0
   */
  value: number;
}

/**
 * Options accepted by {@link CapacitorAudioRecorderPlugin.startRecording}.
 *
 * @since 1.0.0
 */
export interface StartRecordingOptions {
  /**
   * The audio session category options for recording. Only available on iOS.
   *
   * @since 1.0.0
   */
  audioSessionCategoryOptions?: AudioSessionCategoryOption[];

  /**
   * The audio session mode for recording. Only available on iOS.
   *
   * @since 1.0.0
   */
  audioSessionMode?: AudioSessionMode;

  /**
   * The audio bit rate in bytes per second.
   * Only available on Android and iOS.
   *
   * @since 1.0.0
   */
  bitRate?: number;

  /**
   * The audio sample rate in Hz.
   * Only available on Android and iOS.
   *
   * @since 1.0.0
   */
  sampleRate?: number;

  /**
   * When `true`, reset the iOS `AVAudioSession` category to `.playback` when
   * recording stops or is canceled. This avoids quiet in-app playback of the
   * just-recorded file while the session is still configured for
   * `.playAndRecord`.
   *
   * Only available on iOS.
   *
   * @since 8.2.10
   */
  resetToPlaybackOnStop?: boolean;

  /**
   * The container the recording is written in. Only available on Android and iOS.
   *
   * - `'m4a'`: MPEG-4 (AAC in an `.m4a` file). Its index is written when the recording stops, so a
   *   recording that ends in a crash, a force-quit or an empty battery is unreadable.
   * - `'aac'`: ADTS (AAC in an `.aac` file), a stream of self-contained frames. A recording that
   *   ends badly stays readable up to its last frame, and on iOS the segments of an interrupted
   *   recording are joined byte for byte when it stops, without re-encoding.
   *
   * @default 'm4a'
   * @since 8.4.0
   */
  format?: RecordingFormat;
}

/**
 * The container of a recording; see {@link StartRecordingOptions.format}.
 *
 * @since 8.4.0
 */
export type RecordingFormat = 'm4a' | 'aac';

/**
 * Result returned by {@link CapacitorAudioRecorderPlugin.stopRecording}.
 *
 * @since 1.0.0
 */
export interface StopRecordingResult {
  /**
   * The recorded audio as a Blob. Only available on Web.
   *
   * @since 1.0.0
   */
  blob?: Blob;

  /**
   * The duration of the recording in milliseconds.
   *
   * @since 1.0.0
   */
  duration?: number;

  /**
   * The URI pointing to the recorded file. Only available on Android and iOS.
   *
   * @since 1.0.0
   */
  uri?: string;

  /**
   * `true` when the segments of an interrupted recording could not be joined. `uri` then points
   * to the longest segment, and `segments` lists all of them. Only available on iOS.
   *
   * @since 8.4.0
   */
  mergeFailed?: boolean;

  /**
   * The URIs of every segment of the recording, in recording order, when `mergeFailed` is `true`.
   * They stay on disk, so the caller can still join them. Only available on iOS.
   *
   * @since 8.4.0
   */
  segments?: string[];
}

/**
 * Permission information returned by {@link CapacitorAudioRecorderPlugin.checkPermissions}
 * and {@link CapacitorAudioRecorderPlugin.requestPermissions}.
 *
 * @since 1.0.0
 */
export interface PermissionStatus {
  /**
   * The permission state for audio recording.
   *
   * @since 1.0.0
   */
  recordAudio: PermissionState;
}

/**
 * Event emitted when an error occurs during recording.
 *
 * @since 1.0.0
 */
export interface RecordingErrorEvent {
  /**
   * The error message.
   *
   * @since 1.0.0
   */
  message: string;

  /**
   * URI of the most recently preserved segment when the error occurred.
   *
   * Emitted on iOS. The segment may be partial. May be an empty string when no
   * segment was preserved yet.
   *
   * @since 8.2.0
   */
  uri?: string;
}

/**
 * Event emitted when an audio session interruption ends on iOS (for example after a phone call).
 *
 * @since 8.2.0
 */
export interface RecordingInterruptionEndedEvent {
  /**
   * Whether the plugin resumed recording after the interruption.
   *
   * @since 8.2.0
   */
  shouldResume: boolean;
}

/**
 * Event emitted when a recording completes.
 *
 * @since 1.0.0
 */
export type RecordingStoppedEvent = StopRecordingResult;

/**
 * The recording status.
 *
 * @since 1.0.0
 */
export enum RecordingStatus {
  Inactive = 'INACTIVE',
  Recording = 'RECORDING',
  Paused = 'PAUSED',
}

/**
 * Audio session category options available on iOS.
 *
 * @since 1.0.0
 */
export enum AudioSessionCategoryOption {
  AllowAirPlay = 'ALLOW_AIR_PLAY',
  AllowBluetooth = 'ALLOW_BLUETOOTH',
  AllowBluetoothA2DP = 'ALLOW_BLUETOOTH_A2DP',
  DefaultToSpeaker = 'DEFAULT_TO_SPEAKER',
  DuckOthers = 'DUCK_OTHERS',
  InterruptSpokenAudioAndMixWithOthers = 'INTERRUPT_SPOKEN_AUDIO_AND_MIX_WITH_OTHERS',
  MixWithOthers = 'MIX_WITH_OTHERS',
  OverrideMutedMicrophoneInterruption = 'OVERRIDE_MUTED_MICROPHONE_INTERRUPTION',
}

/**
 * Audio session modes available on iOS.
 *
 * @since 1.0.0
 */
export enum AudioSessionMode {
  Default = 'DEFAULT',
  GameChat = 'GAME_CHAT',
  Measurement = 'MEASUREMENT',
  SpokenAudio = 'SPOKEN_AUDIO',
  VideoChat = 'VIDEO_CHAT',
  VideoRecording = 'VIDEO_RECORDING',
  VoiceChat = 'VOICE_CHAT',
}

/**
 * Platform permission states supported by Capacitor.
 *
 * @since 1.0.0
 */
export type PermissionState = 'prompt' | 'prompt-with-rationale' | 'granted' | 'denied';

/**
 * Capacitor plugin contract for recording audio.
 *
 * @since 1.0.0
 */
export interface CapacitorAudioRecorderPlugin {
  /**
   * Start recording audio using the device microphone.
   *
   * @param options Recording configuration options.
   * @since 1.0.0
   */
  startRecording(options?: StartRecordingOptions): Promise<void>;

  /**
   * Pause the ongoing recording. Only available on Android (API 24+), iOS, and Web.
   *
   * @since 1.0.0
   */
  pauseRecording(): Promise<void>;

  /**
   * Resume a previously paused recording.
   *
   * @since 1.0.0
   */
  resumeRecording(): Promise<void>;

  /**
   * Stop the current recording and persist the recorded audio.
   *
   * When the recorder cannot stop cleanly, the call is rejected and the recording file is kept on
   * disk; on Android the rejection's `data.uri` points to it.
   *
   * @returns Recording metadata such as duration and URI/blob.
   * @since 1.0.0
   */
  stopRecording(): Promise<StopRecordingResult>;

  /**
   * Cancel the current recording and discard any captured audio.
   *
   * @since 1.0.0
   */
  cancelRecording(): Promise<void>;

  /**
   * Reset the iOS audio session to `.playback` for normal-volume playback of
   * recorded audio in the same app process (for example via an HTML audio
   * element). No-op on Android and Web.
   *
   * @since 8.2.10
   */
  resetAudioSessionForPlayback(): Promise<void>;

  /**
   * Retrieve the current recording status.
   *
   * @since 1.0.0
   */
  getRecordingStatus(): Promise<GetRecordingStatusResult>;

  /**
   * Retrieve the current input amplitude (microphone level) as a normalized
   * number in the `[0, 1]` range.
   *
   * Intended for driving live visualizations such as VU meters or waveforms
   * while recording. Returns `0` when no recording is active. Designed for
   * UI-rate polling — a 60–100 ms interval is a good starting point for a
   * waveform. Avoid calling it in a tight loop; each call crosses the
   * JS/native bridge.
   *
   * @returns The current amplitude.
   * @since 8.1.0
   */
  getCurrentAmplitude(): Promise<GetCurrentAmplitudeResult>;

  /**
   * Return the current permission state for accessing the microphone.
   *
   * @since 1.0.0
   */
  checkPermissions(): Promise<PermissionStatus>;

  /**
   * Request permission to access the microphone.
   *
   * @since 1.0.0
   */
  requestPermissions(): Promise<PermissionStatus>;

  /**
   * Listen for recording errors.
   *
   * @since 1.0.0
   */
  addListener(
    eventName: 'recordingError',
    listenerFunc: (event: RecordingErrorEvent) => void,
  ): Promise<PluginListenerHandle>;

  /**
   * Listen for pause events emitted when a recording is paused.
   *
   * @since 1.0.0
   */
  addListener(eventName: 'recordingPaused', listenerFunc: () => void): Promise<PluginListenerHandle>;

  /**
   * Listen for recording completion events.
   *
   * @since 1.0.0
   */
  addListener(
    eventName: 'recordingStopped',
    listenerFunc: (event: RecordingStoppedEvent) => void,
  ): Promise<PluginListenerHandle>;

  /**
   * Listen for the start of an audio session interruption while recording.
   *
   * Only emitted on iOS when the system pauses or archives the active recording
   * (for example when a phone call begins).
   *
   * @since 8.2.0
   */
  addListener(eventName: 'recordingInterruptionBegan', listenerFunc: () => void): Promise<PluginListenerHandle>;

  /**
   * Listen for the end of an audio session interruption while recording.
   *
   * Only emitted on iOS. Usually follows `recordingInterruptionBegan`, but may
   * also fire after a recorder failure without a prior began event, with
   * `shouldResume` set to `false`.
   *
   * @since 8.2.0
   */
  addListener(
    eventName: 'recordingInterruptionEnded',
    listenerFunc: (event: RecordingInterruptionEndedEvent) => void,
  ): Promise<PluginListenerHandle>;

  /**
   * Remove all registered listeners.
   *
   * @since 1.0.0
   */
  removeAllListeners(): Promise<void>;

  /**
   * Get the native Capacitor plugin version.
   *
   * @returns Promise that resolves with the plugin version
   * @since 1.0.0
   */
  getPluginVersion(): Promise<{ version: string }>;
}
