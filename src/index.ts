import { registerPlugin } from '@capacitor/core';

import type { CapacitorAudioRecorderPlugin } from './definitions';

const CapacitorAudioRecorder = registerPlugin<CapacitorAudioRecorderPlugin>('CapacitorAudioRecorder', {
  web: () => import('./web').then((m) => new m.CapacitorAudioRecorderWeb()),
});

export * from './definitions';
export { CapacitorAudioRecorder };
