import { WebPlugin, type PluginListenerHandle } from '@capacitor/core';

import {
  CapacitorAudioRecorderPlugin,
  PermissionState,
  PermissionStatus,
  RecordingErrorEvent,
  RecordingStatus,
  RecordingStoppedEvent,
  StartRecordingOptions,
  StopRecordingResult,
} from './definitions';

export class CapacitorAudioRecorderWeb extends WebPlugin implements CapacitorAudioRecorderPlugin {
  private mediaRecorder: MediaRecorder | null = null;
  private mediaStream: MediaStream | null = null;
  private recordedChunks: BlobPart[] = [];
  private status: RecordingStatus = RecordingStatus.Inactive;
  private startTimestamp: number | null = null;
  private pausedTimestamp: number | null = null;
  private accumulatedPauseDuration = 0;
  private stopResolver: ((result: StopRecordingResult) => void) | null = null;
  private stopRejector: ((reason?: any) => void) | null = null;

  async startRecording(_options?: StartRecordingOptions): Promise<void> {
    if (this.status === RecordingStatus.Recording || this.status === RecordingStatus.Paused) {
      throw this.unavailable('Recording already in progress.');
    }

    await this.ensurePermission(true);

    try {
      this.mediaStream = await navigator.mediaDevices.getUserMedia({ audio: true });
    } catch (error) {
      this.handleError(`Unable to acquire microphone: ${(error as Error)?.message ?? error}`);
      throw error;
    }

    const mimeType = this.pickMimeType();
    try {
      this.mediaRecorder = new MediaRecorder(this.mediaStream, mimeType ? { mimeType } : undefined);
    } catch (error) {
      this.cleanupMediaStream();
      this.handleError(`Unable to initialise MediaRecorder: ${(error as Error)?.message ?? error}`);
      throw error;
    }

    this.recordedChunks = [];
    this.startTimestamp = Date.now();
    this.accumulatedPauseDuration = 0;
    this.pausedTimestamp = null;

    this.mediaRecorder.addEventListener('dataavailable', (event: BlobEvent) => {
      if (event.data.size > 0) {
        this.recordedChunks.push(event.data);
      }
    });

    this.mediaRecorder.addEventListener('stop', () => {
      const result = this.buildStopResult();
      if (this.stopResolver) {
        this.stopResolver(result);
      }
      this.notifyListeners('recordingStopped', result as RecordingStoppedEvent);
      this.resetStopHandlers();
      this.resetState();
    });

    this.mediaRecorder.addEventListener('error', (event: Event) => {
      const message = (event as any)?.error?.message ?? 'Recording error.';
      this.handleError(message);
      if (this.stopRejector) {
        this.stopRejector(new Error(message));
      }
      this.resetStopHandlers();
      this.resetState();
    });

    this.mediaRecorder.start();
    this.status = RecordingStatus.Recording;
  }

  async pauseRecording(): Promise<void> {
    if (!this.mediaRecorder || this.status !== RecordingStatus.Recording) {
      throw this.unavailable('No active recording to pause.');
    }
    if (this.supportsRecorderPause()) {
      this.mediaRecorder.pause();
      this.status = RecordingStatus.Paused;
      this.pausedTimestamp = Date.now();
      this.notifyListeners('recordingPaused', {});
    } else {
      throw this.unavailable('Pausing recordings is not supported in this browser.');
    }
  }

  async resumeRecording(): Promise<void> {
    if (!this.mediaRecorder || this.status !== RecordingStatus.Paused) {
      throw this.unavailable('No paused recording to resume.');
    }
    if (this.supportsRecorderPause()) {
      this.mediaRecorder.resume();
      if (this.pausedTimestamp) {
        this.accumulatedPauseDuration += Date.now() - this.pausedTimestamp;
      }
      this.pausedTimestamp = null;
      this.status = RecordingStatus.Recording;
    } else {
      throw this.unavailable('Resuming recordings is not supported in this browser.');
    }
  }

  async stopRecording(): Promise<StopRecordingResult> {
    if (!this.mediaRecorder || this.status === RecordingStatus.Inactive) {
      throw this.unavailable('No active recording to stop.');
    }

    if (this.status === RecordingStatus.Paused && this.pausedTimestamp) {
      this.accumulatedPauseDuration += Date.now() - this.pausedTimestamp;
      this.pausedTimestamp = null;
    }

    const stopPromise = new Promise<StopRecordingResult>((resolve, reject) => {
      this.stopResolver = resolve;
      this.stopRejector = reject;
    });

    try {
      this.mediaRecorder.stop();
    } catch (error) {
      this.resetStopHandlers();
      this.resetState();
      this.handleError(`Unable to stop recorder: ${(error as Error)?.message ?? error}`);
      throw error;
    }

    return stopPromise;
  }

  async cancelRecording(): Promise<void> {
    if (!this.mediaRecorder || this.status === RecordingStatus.Inactive) {
      this.resetState();
      return;
    }

    try {
      this.mediaRecorder.stop();
    } catch {
      // Ignored.
    }

    this.resetStopHandlers();
    this.resetState();
  }

  async getRecordingStatus(): Promise<{ status: RecordingStatus }> {
    return { status: this.status };
  }

  async checkPermissions(): Promise<PermissionStatus> {
    const state = await this.getPermissionState();
    return { recordAudio: state };
  }

  async requestPermissions(): Promise<PermissionStatus> {
    const state = await this.ensurePermission(true);
    return { recordAudio: state };
  }

  async addListener<T extends 'recordingError' | 'recordingPaused' | 'recordingStopped'>(
    eventName: T,
    listenerFunc: T extends 'recordingError'
      ? (event: RecordingErrorEvent) => void
      : T extends 'recordingStopped'
        ? (event: RecordingStoppedEvent) => void
        : () => void,
  ): Promise<PluginListenerHandle> {
    return super.addListener(eventName, listenerFunc as any);
  }

  async removeAllListeners(): Promise<void> {
    await super.removeAllListeners();
  }

  // Helpers

  private supportsRecorderPause(): boolean {
    return !!this.mediaRecorder && typeof this.mediaRecorder.pause === 'function' && typeof this.mediaRecorder.resume === 'function';
  }

  private pickMimeType(): string | undefined {
    const preferred = ['audio/webm;codecs=opus', 'audio/ogg;codecs=opus', 'audio/mp4'];
    for (const type of preferred) {
      if ((window as any).MediaRecorder && MediaRecorder.isTypeSupported && MediaRecorder.isTypeSupported(type)) {
        return type;
      }
    }
    return undefined;
  }

  private buildStopResult(): StopRecordingResult {
    const blob = this.recordedChunks.length > 0 ? new Blob(this.recordedChunks, { type: this.pickMimeType() || 'audio/webm' }) : undefined;
    let duration: number | undefined;
    if (this.startTimestamp) {
      duration = Date.now() - this.startTimestamp - this.accumulatedPauseDuration;
    }
    return {
      blob,
      duration,
    };
  }

  private resetStopHandlers(): void {
    this.stopResolver = null;
    this.stopRejector = null;
  }

  private resetState(): void {
    this.status = RecordingStatus.Inactive;
    this.startTimestamp = null;
    this.pausedTimestamp = null;
    this.accumulatedPauseDuration = 0;
    this.recordedChunks = [];
    this.cleanupMediaStream();
    if (this.mediaRecorder) {
      const recorder = this.mediaRecorder;
      recorder.ondataavailable = null;
      recorder.onstop = null;
      recorder.onerror = null;
    }
    this.mediaRecorder = null;
  }

  private cleanupMediaStream(): void {
    if (this.mediaStream) {
      this.mediaStream.getTracks().forEach((track) => track.stop());
    }
    this.mediaStream = null;
  }

  private async ensurePermission(request: boolean): Promise<PermissionState> {
    const currentState = await this.getPermissionState();
    if (currentState === 'granted' || !request) {
      return currentState;
    }

    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      stream.getTracks().forEach((track) => track.stop());
      return 'granted';
    } catch (error) {
      return 'denied';
    }
  }

  private async getPermissionState(): Promise<PermissionState> {
    if (!navigator.permissions?.query) {
      return 'prompt';
    }

    try {
      const result = await navigator.permissions.query({ name: 'microphone' as PermissionName });
      switch (result.state) {
        case 'granted':
          return 'granted';
        case 'denied':
          return 'denied';
        default:
          return 'prompt';
      }
    } catch {
      return 'prompt';
    }
  }

  private handleError(message: string): void {
    this.status = RecordingStatus.Inactive;
    this.notifyListeners('recordingError', { message });
  }
}
