import './style.css';
import {
  CapacitorAudioRecorder,
  RecordingStatus,
} from '@capgo/capacitor-audio-recorder';
import { Filesystem } from '@capacitor/filesystem';
import { Capacitor } from '@capacitor/core';

const statusLabel = document.getElementById('status');
const permissionLabel = document.getElementById('permission');
const durationLabel = document.getElementById('duration');
const uriLabel = document.getElementById('uri');
const fileSizeLabel = document.getElementById('file-size');
const fileSizeFetchLabel = document.getElementById('file-size-fetch');
const messageLabel = document.getElementById('message');

const startButton = document.getElementById('start-recording');
const pauseButton = document.getElementById('pause-recording');
const resumeButton = document.getElementById('resume-recording');
const stopButton = document.getElementById('stop-recording');
const cancelButton = document.getElementById('cancel-recording');
const readFileButton = document.getElementById('read-file');
const readFileFetchButton = document.getElementById('read-file-fetch');
const statusButton = document.getElementById('refresh-status');

let lastRecordedUri = null;
let lastRecordedBlob = null;

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

readFileButton.addEventListener('click', async () => {
  if (!lastRecordedUri) {
    showMessage('No recorded file URI available. Please record first.');
    return;
  }

  try {
    showMessage('Reading file...');
    
    // Convert file:// URI to a path that Filesystem API can use
    // On iOS: file:///var/mobile/... -> /var/mobile/...
    // On Android: file:///data/data/... -> /data/data/...
    let filePath = lastRecordedUri;
    if (filePath.startsWith('file://')) {
      filePath = filePath.replace('file://', '');
    }

    // Read the file using Filesystem API
    // For binary audio files, read without encoding to get base64 data
    const result = await Filesystem.readFile({
      path: filePath,
    });

    // Calculate file size from base64 data
    // Base64 encoding increases size by ~33%, so decode to get actual binary size
    if (result.data) {
      const base64Length = result.data.length;
      // Base64 is 4/3 the size of binary data
      const estimatedBinarySize = Math.round((base64Length * 3) / 4);
      fileSizeLabel.textContent = `~${estimatedBinarySize} bytes (read via Filesystem API)`;
      showMessage(`File read successfully. Base64 length: ${base64Length} chars`);
    } else {
      fileSizeLabel.textContent = 'Unknown size';
      showMessage('File read but no data returned.');
    }
  } catch (error) {
    fileSizeLabel.textContent = 'Error reading file';
    showMessage(`Failed to read file: ${error?.message ?? String(error)}`);
  }
});

readFileFetchButton.addEventListener('click', async () => {
  try {
    showMessage('Reading file via fetch...');

    // Handle web platform (blob)
    if (lastRecordedBlob) {
      // For web, we already have the blob, so we can get its size directly
      const blobSize = lastRecordedBlob.size;
      fileSizeFetchLabel.textContent = `${blobSize} bytes (read via Fetch from Blob)`;
      showMessage(`Blob size: ${blobSize} bytes`);
      return;
    }

    // Handle native platforms (URI)
    if (!lastRecordedUri) {
      showMessage('No recorded file URI available. Please record first.');
      return;
    }

    // Convert file:// URI to a fetchable URL using Capacitor's convertFileSrc
    // This converts file:// URIs to capacitor:// URLs that can be fetched
    const fetchableUrl = Capacitor.convertFileSrc(lastRecordedUri);

    // Fetch the file
    const response = await fetch(fetchableUrl);
    
    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }

    // Get the file as a blob
    const blob = await response.blob();
    const fileSize = blob.size;

    fileSizeFetchLabel.textContent = `${fileSize} bytes (read via Fetch API)`;
    showMessage(`File read successfully via fetch. Size: ${fileSize} bytes`);
  } catch (error) {
    fileSizeFetchLabel.textContent = 'Error reading file';
    showMessage(`Failed to read file via fetch: ${error?.message ?? String(error)}`);
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
    lastRecordedUri = result.uri;
    lastRecordedBlob = null;
    readFileButton.disabled = false;
    readFileFetchButton.disabled = false;
    fileSizeLabel.textContent = '—';
    fileSizeFetchLabel.textContent = '—';
  } else if (result.blob) {
    uriLabel.textContent = `Blob size: ${result.blob.size} bytes`;
    lastRecordedUri = null;
    lastRecordedBlob = result.blob;
    readFileButton.disabled = true;
    readFileFetchButton.disabled = false;
    fileSizeLabel.textContent = '—';
    fileSizeFetchLabel.textContent = '—';
  } else {
    uriLabel.textContent = 'Unavailable';
    lastRecordedUri = null;
    lastRecordedBlob = null;
    readFileButton.disabled = true;
    readFileFetchButton.disabled = true;
    fileSizeLabel.textContent = '—';
    fileSizeFetchLabel.textContent = '—';
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
