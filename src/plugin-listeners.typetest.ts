/**
 * Compile-only assertions for plugin listener typings (not bundled).
 */
import type { CapacitorAudioRecorderPlugin, RecordingErrorEvent, RecordingInterruptionEndedEvent } from './definitions';

declare const plugin: CapacitorAudioRecorderPlugin;

void plugin.addListener('recordingInterruptionBegan', () => {});

void plugin.addListener('recordingInterruptionEnded', (event: RecordingInterruptionEndedEvent) => {
  const resume: boolean = event.shouldResume;
  void resume;
});

void plugin.addListener('recordingError', (event: RecordingErrorEvent) => {
  const message: string = event.message;
  const uri: string | undefined = event.uri;
  void message;
  void uri;
});

export {};
