# Example App for `@capgo/capacitor-audio-recorder`

This Vite project links directly to the local plugin source so you can exercise recording, pause/resume, and stop flows while developing the native implementation.

## Playground actions

- **Start recording** – Requests microphone permissions (if needed) and begins capturing audio.
- **Pause / Resume** – Toggles recording without losing the current buffer (requires Android API 24+, iOS, or Web support).
- **Stop recording** – Finalises the recording and prints the resulting duration and file URI / blob reference.
- **Cancel** – Aborts the session and discards any captured audio.
- **Refresh status** – Queries the plugin for the current `RecordingStatus`.

## Getting started

```bash
npm install
npm start
```

Add native shells with `npx cap add ios` or `npx cap add android` from this folder to try behaviour on device or simulator.
