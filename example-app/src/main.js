import './style.css';
import {
  CapacitorAudioRecorder,
  RecordingStatus,
} from '@capgo/capacitor-audio-recorder';

const statusLabel = document.getElementById('status');
const permissionLabel = document.getElementById('permission');
const durationLabel = document.getElementById('duration');
const uriLabel = document.getElementById('uri');
const messageLabel = document.getElementById('message');

const startButton = document.getElementById('start-recording');
const pauseButton = document.getElementById('pause-recording');
const resumeButton = document.getElementById('resume-recording');
const stopButton = document.getElementById('stop-recording');
const cancelButton = document.getElementById('cancel-recording');
const statusButton = document.getElementById('refresh-status');

let isSupported = true;

function showMessage(text) {
  if (!messageLabel) return;
  messageLabel.textContent = text ?? '';
}

function updateStatus(status) {
  statusLabel.textContent = status;
  startButton.disabled = status === RecordingStatus.Recording || status === RecordingStatus.Paused || !isSupported;
  pauseButton.disabled = status !== RecordingStatus.Recording;
  resumeButton.disabled = status !== RecordingStatus.Paused;
  stopButton.disabled = status === RecordingStatus.Inactive;
  cancelButton.disabled = status === RecordingStatus.Inactive;
}

async function refreshPermission() {
  const { recordAudio } = await CapacitorAudioRecorder.checkPermissions();
  permissionLabel.textContent = recordAudio;
  return recordAudio;
}

async function ensurePermission() {
  const state = await refreshPermission();
  if (state === 'granted') {
    return;
  }
  const result = await CapacitorAudioRecorder.requestPermissions();
  permissionLabel.textContent = result.recordAudio;
  if (result.recordAudio !== 'granted') {
    throw new Error(`Permission not granted: ${result.recordAudio}`);
  }
}

async function refreshStatus() {
  const { status } = await CapacitorAudioRecorder.getRecordingStatus();
  updateStatus(status);
}

startButton.addEventListener('click', async () => {
  try {
    await ensurePermission();
    await CapacitorAudioRecorder.startRecording();
    updateStatus(RecordingStatus.Recording);
    showMessage('Recording started.');
  } catch (error) {
    showMessage(error?.message ?? String(error));
  }
});

pauseButton.addEventListener('click', async () => {
  try {
    await CapacitorAudioRecorder.pauseRecording();
    updateStatus(RecordingStatus.Paused);
    showMessage('Recording paused.');
  } catch (error) {
    showMessage(error?.message ?? String(error));
  }
});

resumeButton.addEventListener('click', async () => {
  try {
    await CapacitorAudioRecorder.resumeRecording();
    updateStatus(RecordingStatus.Recording);
    showMessage('Recording resumed.');
  } catch (error) {
    showMessage(error?.message ?? String(error));
  }
});

stopButton.addEventListener('click', async () => {
  try {
    const result = await CapacitorAudioRecorder.stopRecording();
    applyStopResult(result);
    showMessage('Recording saved.');
  } catch (error) {
    showMessage(error?.message ?? String(error));
  }
});

cancelButton.addEventListener('click', async () => {
  try {
    await CapacitorAudioRecorder.cancelRecording();
    updateStatus(RecordingStatus.Inactive);
    showMessage('Recording cancelled.');
  } catch (error) {
    showMessage(error?.message ?? String(error));
  }
});

statusButton.addEventListener('click', () => {
  refreshStatus().catch((error) => showMessage(error?.message ?? String(error)));
});

CapacitorAudioRecorder.addListener('recordingPaused', () => {
  updateStatus(RecordingStatus.Paused);
  showMessage('Recording paused.');
});

CapacitorAudioRecorder.addListener('recordingStopped', (event) => {
  applyStopResult(event);
  showMessage('Recording stopped.');
});

CapacitorAudioRecorder.addListener('recordingError', (event) => {
  updateStatus(RecordingStatus.Inactive);
  showMessage(event.message ?? 'Recording error.');
});

function applyStopResult(result) {
  updateStatus(RecordingStatus.Inactive);
  if (typeof result.duration === 'number') {
    durationLabel.textContent = `${Math.round(result.duration)} ms`;
  }
  if (result.uri) {
    uriLabel.textContent = result.uri;
  } else if (result.blob) {
    uriLabel.textContent = `Blob size: ${result.blob.size} bytes`;
  } else {
    uriLabel.textContent = 'Unavailable';
  }
}

(async () => {
  try {
    await refreshPermission();
    await refreshStatus();
  } catch (error) {
    isSupported = false;
    updateStatus('UNAVAILABLE');
    showMessage(error?.message ?? String(error));
  }
})();
