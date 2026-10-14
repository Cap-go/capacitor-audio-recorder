package app.capgo.audiorecorder;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.mockConstruction;
import static org.mockito.Mockito.mockStatic;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import android.media.MediaRecorder;
import android.net.Uri;
import android.os.SystemClock;
import com.getcapacitor.JSObject;
import com.getcapacitor.PluginCall;
import java.io.File;
import java.lang.reflect.Field;
import org.junit.Test;
import org.mockito.InOrder;
import org.mockito.MockedConstruction;
import org.mockito.MockedStatic;

/**
 * A recording must survive what ends it badly: a stop that fails, and the plugin being destroyed
 * while it records. And `format: 'aac'` must give ADTS, the container that survives a crash.
 */
public class RecordingDurabilityTest {

    @Test
    public void aacFormat_writesAdts_everythingElseMpeg4() {
        assertEquals(MediaRecorder.OutputFormat.AAC_ADTS, CapacitorAudioRecorderPlugin.outputFormatFor("aac"));
        assertEquals(MediaRecorder.OutputFormat.AAC_ADTS, CapacitorAudioRecorderPlugin.outputFormatFor("AAC"));
        assertEquals(MediaRecorder.OutputFormat.MPEG_4, CapacitorAudioRecorderPlugin.outputFormatFor("m4a"));
        assertEquals(MediaRecorder.OutputFormat.MPEG_4, CapacitorAudioRecorderPlugin.outputFormatFor(null));
        assertEquals("aac", CapacitorAudioRecorderPlugin.fileExtensionFor("aac"));
        assertEquals("m4a", CapacitorAudioRecorderPlugin.fileExtensionFor(null));
    }

    @Test
    public void stopRecording_whenStopFails_keepsTheFileAndHandsBackItsUri() throws Exception {
        CapacitorAudioRecorderPlugin plugin = new CapacitorAudioRecorderPlugin();
        MediaRecorder recorder = mock(MediaRecorder.class);
        doThrow(new RuntimeException("stop failed")).when(recorder).stop();
        File file = File.createTempFile("recording-", ".aac");
        file.deleteOnExit();
        set(plugin, "mediaRecorder", recorder);
        set(plugin, "outputFile", file);
        setStatus(plugin, "RECORDING");
        PluginCall call = mock(PluginCall.class);
        Uri uri = mock(Uri.class);
        when(uri.toString()).thenReturn("file://" + file.getAbsolutePath());

        try (
            MockedStatic<Uri> uris = mockStatic(Uri.class);
            MockedStatic<SystemClock> clock = mockStatic(SystemClock.class);
            MockedConstruction<JSObject> data = mockConstruction(JSObject.class)
        ) {
            uris.when(() -> Uri.fromFile(file)).thenReturn(uri);
            clock.when(SystemClock::elapsedRealtime).thenReturn(5_000L);
            plugin.stopRecording(call);

            assertTrue("A failed stop must not delete the recording", file.exists());
            assertEquals(1, data.constructed().size());
            verify(data.constructed().get(0)).put("uri", "file://" + file.getAbsolutePath());
            verify(call).reject(
                eq("Failed to stop recording cleanly. The recording file was preserved."),
                isNull(),
                any(Exception.class),
                eq(data.constructed().get(0))
            );
        }
        verify(recorder).release();
        assertNull(get(plugin, "outputFile"));
    }

    @Test
    public void handleOnDestroy_whileRecording_stopsBeforeReleasing() throws Exception {
        CapacitorAudioRecorderPlugin plugin = new CapacitorAudioRecorderPlugin();
        MediaRecorder recorder = mock(MediaRecorder.class);
        File file = File.createTempFile("recording-", ".aac");
        file.deleteOnExit();
        set(plugin, "mediaRecorder", recorder);
        set(plugin, "outputFile", file);
        setStatus(plugin, "RECORDING");

        plugin.handleOnDestroy();

        InOrder order = inOrder(recorder);
        order.verify(recorder).stop();
        order.verify(recorder).release();
        assertTrue(file.exists());
    }

    @Test
    public void handleOnDestroy_whenAStopThrows_stillReleasesAndKeepsTheFile() throws Exception {
        CapacitorAudioRecorderPlugin plugin = new CapacitorAudioRecorderPlugin();
        MediaRecorder recorder = mock(MediaRecorder.class);
        doThrow(new IllegalStateException("not started")).when(recorder).stop();
        File file = File.createTempFile("recording-", ".aac");
        file.deleteOnExit();
        set(plugin, "mediaRecorder", recorder);
        set(plugin, "outputFile", file);
        setStatus(plugin, "PAUSED");

        plugin.handleOnDestroy();

        verify(recorder).release();
        assertTrue(file.exists());
    }

    @Test
    public void handleOnDestroy_whenNotRecording_doesNotStop() throws Exception {
        CapacitorAudioRecorderPlugin plugin = new CapacitorAudioRecorderPlugin();
        MediaRecorder recorder = mock(MediaRecorder.class);
        set(plugin, "mediaRecorder", recorder);
        setStatus(plugin, "INACTIVE");

        plugin.handleOnDestroy();

        verify(recorder, never()).stop();
        verify(recorder).release();
        assertFalse(get(plugin, "mediaRecorder") != null);
    }

    private static void set(CapacitorAudioRecorderPlugin plugin, String name, Object value) throws Exception {
        Field field = CapacitorAudioRecorderPlugin.class.getDeclaredField(name);
        field.setAccessible(true);
        field.set(plugin, value);
    }

    private static Object get(CapacitorAudioRecorderPlugin plugin, String name) throws Exception {
        Field field = CapacitorAudioRecorderPlugin.class.getDeclaredField(name);
        field.setAccessible(true);
        return field.get(plugin);
    }

    private static void setStatus(CapacitorAudioRecorderPlugin plugin, String statusName) throws Exception {
        Field field = CapacitorAudioRecorderPlugin.class.getDeclaredField("status");
        field.setAccessible(true);
        for (Object value : field.getType().getEnumConstants()) {
            if (((Enum<?>) value).name().equals(statusName)) {
                field.set(plugin, value);
                return;
            }
        }
        throw new IllegalArgumentException("Unknown status: " + statusName);
    }
}
