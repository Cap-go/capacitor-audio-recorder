package app.capgo.audiorecorder;

import android.Manifest;
import android.media.MediaRecorder;
import android.net.Uri;
import android.os.Build;
import android.os.SystemClock;
import androidx.annotation.Nullable;
import com.getcapacitor.JSObject;
import com.getcapacitor.PermissionState;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import com.getcapacitor.annotation.Permission;
import com.getcapacitor.annotation.PermissionCallback;
import java.io.File;
import java.io.IOException;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

@CapacitorPlugin(
    name = "CapacitorAudioRecorder",
    permissions = { @Permission(alias = "microphone", strings = { Manifest.permission.RECORD_AUDIO }) }
)
public class CapacitorAudioRecorderPlugin extends com.getcapacitor.Plugin {

    private final String PLUGIN_VERSION = "7.1.0";

    private enum RecordingStatus {
        INACTIVE,
        RECORDING,
        PAUSED
    }

    private MediaRecorder mediaRecorder;
    private File outputFile;
    private RecordingStatus status = RecordingStatus.INACTIVE;
    private long recordingStartTime = 0L;
    private long pauseStartTime = 0L;
    private long accumulatedPauseDuration = 0L;

    @PluginMethod
    public void startRecording(PluginCall call) {
        if (status != RecordingStatus.INACTIVE) {
            call.reject("Recording already in progress.");
            return;
        }

        if (!ensurePermission(call)) {
            return;
        }

        int bitRate = call.getInt("bitRate", 192000);
        int sampleRate = call.getInt("sampleRate", 44100);

        try {
            prepareRecorder(bitRate, sampleRate);
            mediaRecorder.start();
            recordingStartTime = SystemClock.elapsedRealtime();
            accumulatedPauseDuration = 0;
            pauseStartTime = 0;
            status = RecordingStatus.RECORDING;
            call.resolve();
        } catch (IOException ex) {
            releaseRecorder();
            call.reject("Unable to start recording.", ex);
        } catch (IllegalStateException ex) {
            releaseRecorder();
            call.reject("Recording failed to start.", ex);
        }
    }

    @PluginMethod
    public void pauseRecording(PluginCall call) {
        if (status != RecordingStatus.RECORDING || mediaRecorder == null) {
            call.reject("No active recording to pause.");
            return;
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            call.reject("Pausing is not supported on this Android version.");
            return;
        }

        try {
            mediaRecorder.pause();
            pauseStartTime = SystemClock.elapsedRealtime();
            status = RecordingStatus.PAUSED;
            notifyListeners("recordingPaused", new JSObject());
            call.resolve();
        } catch (IllegalStateException ex) {
            call.reject("Failed to pause recording.", ex);
        }
    }

    @PluginMethod
    public void resumeRecording(PluginCall call) {
        if (status != RecordingStatus.PAUSED || mediaRecorder == null) {
            call.reject("No paused recording to resume.");
            return;
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            call.reject("Resuming is not supported on this Android version.");
            return;
        }

        try {
            mediaRecorder.resume();
            if (pauseStartTime > 0) {
                accumulatedPauseDuration += SystemClock.elapsedRealtime() - pauseStartTime;
            }
            pauseStartTime = 0;
            status = RecordingStatus.RECORDING;
            call.resolve();
        } catch (IllegalStateException ex) {
            call.reject("Failed to resume recording.", ex);
        }
    }

    @PluginMethod
    public void stopRecording(PluginCall call) {
        if (status == RecordingStatus.INACTIVE || mediaRecorder == null) {
            call.reject("No active recording to stop.");
            return;
        }

        try {
            mediaRecorder.stop();
        } catch (RuntimeException ex) {
            deleteOutputFile();
            releaseRecorder();
            call.reject("Failed to stop recording cleanly.", ex);
            return;
        }

        long duration = calculateDuration();
        String uri = outputFile != null ? Uri.fromFile(outputFile).toString() : "";

        JSObject result = new JSObject();
        result.put("duration", duration);
        result.put("uri", uri);

        notifyListeners("recordingStopped", result);
        releaseRecorder();
        call.resolve(result);
    }

    @PluginMethod
    public void cancelRecording(PluginCall call) {
        if (mediaRecorder != null) {
            try {
                mediaRecorder.stop();
            } catch (RuntimeException ignored) {}
        }
        deleteOutputFile();
        releaseRecorder();
        call.resolve();
    }

    @PluginMethod
    public void getRecordingStatus(PluginCall call) {
        JSObject result = new JSObject();
        result.put("status", status.name());
        call.resolve(result);
    }

    @PluginMethod
    public void checkPermissions(PluginCall call) {
        PermissionState state = getPermissionState("microphone");
        JSObject result = new JSObject();
        result.put("recordAudio", toPermissionString(state));
        call.resolve(result);
    }

    @PluginMethod
    public void requestPermissions(PluginCall call) {
        if (getPermissionState("microphone") == PermissionState.GRANTED) {
            JSObject result = new JSObject();
            result.put("recordAudio", "granted");
            call.resolve(result);
            return;
        }
        requestPermissionForAlias("microphone", call, "microphonePermissionCallback");
    }

    @PermissionCallback
    public void microphonePermissionCallback(PluginCall call) {
        PermissionState state = getPermissionState("microphone");
        JSObject result = new JSObject();
        result.put("recordAudio", toPermissionString(state));
        call.resolve(result);
    }

    @PluginMethod
    public void removeAllListeners(PluginCall call) {
        super.removeAllListeners(call);
    }

    @Override
    protected void handleOnDestroy() {
        super.handleOnDestroy();
        releaseRecorder();
    }

    private boolean ensurePermission(PluginCall call) {
        PermissionState state = getPermissionState("microphone");
        if (state == PermissionState.GRANTED) {
            return true;
        }
        requestPermissionForAlias("microphone", call, "microphonePermissionStartCallback");
        return false;
    }

    @PermissionCallback
    public void microphonePermissionStartCallback(PluginCall call) {
        if (getPermissionState("microphone") != PermissionState.GRANTED) {
            call.reject("Microphone permission not granted.");
            return;
        }
        startRecording(call);
    }

    private void prepareRecorder(int bitRate, int sampleRate) throws IOException {
        releaseRecorder();
        mediaRecorder = new MediaRecorder();
        mediaRecorder.setAudioSource(MediaRecorder.AudioSource.MIC);
        mediaRecorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4);
        mediaRecorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC);
        mediaRecorder.setAudioEncodingBitRate(bitRate);
        mediaRecorder.setAudioSamplingRate(sampleRate);

        File outputDirectory = new File(getContext().getCacheDir(), "capacitor-audio-recorder");
        if (!outputDirectory.exists()) {
            //noinspection ResultOfMethodCallIgnored
            outputDirectory.mkdirs();
        }

        String fileName = "recording-" + new SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(new Date()) + ".m4a";
        outputFile = new File(outputDirectory, fileName);
        mediaRecorder.setOutputFile(outputFile.getAbsolutePath());
        mediaRecorder.prepare();
    }

    private void releaseRecorder() {
        if (mediaRecorder != null) {
            mediaRecorder.reset();
            mediaRecorder.release();
        }
        mediaRecorder = null;
        status = RecordingStatus.INACTIVE;
        recordingStartTime = 0;
        pauseStartTime = 0;
        accumulatedPauseDuration = 0;
    }

    private void deleteOutputFile() {
        if (outputFile != null && outputFile.exists()) {
            //noinspection ResultOfMethodCallIgnored
            outputFile.delete();
        }
        outputFile = null;
    }

    private long calculateDuration() {
        long endTime = SystemClock.elapsedRealtime();
        if (pauseStartTime > 0) {
            accumulatedPauseDuration += endTime - pauseStartTime;
        }
        long duration = endTime - recordingStartTime - accumulatedPauseDuration;
        return Math.max(duration, 0);
    }

    private String toPermissionString(PermissionState state) {
        switch (state) {
            case GRANTED:
                return "granted";
            case DENIED:
                return "denied";
            case PROMPT_WITH_RATIONALE:
                return "prompt-with-rationale";
            default:
                return "prompt";
        }
    }

    @PluginMethod
    public void getPluginVersion(final PluginCall call) {
        try {
            final JSObject ret = new JSObject();
            ret.put("version", this.PLUGIN_VERSION);
            call.resolve(ret);
        } catch (final Exception e) {
            call.reject("Could not get plugin version", e);
        }
    }
}
