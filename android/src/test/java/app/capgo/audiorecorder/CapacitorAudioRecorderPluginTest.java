package app.capgo.audiorecorder;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;
import static org.mockito.Mockito.mock;

import com.getcapacitor.PluginCall;
import java.io.File;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import org.junit.Test;

/**
 * Regression tests for recording file lifecycle (issue #24).
 */
public class CapacitorAudioRecorderPluginTest {

    @Test
    public void releaseRecorder_clearsOutputFileWithoutDeleting() throws Exception {
        CapacitorAudioRecorderPlugin plugin = new CapacitorAudioRecorderPlugin();
        File tempFile = File.createTempFile("recording-", ".m4a");
        tempFile.deleteOnExit();
        assertTrue(tempFile.exists());

        setOutputFile(plugin, tempFile);
        invokeReleaseRecorder(plugin);

        assertNull(getOutputFile(plugin));
        assertTrue("Stopped recording file must remain on disk", tempFile.exists());
    }

    @Test
    public void cancelRecording_whenInactive_doesNotDeleteOutputFile() throws Exception {
        CapacitorAudioRecorderPlugin plugin = new CapacitorAudioRecorderPlugin();
        File tempFile = File.createTempFile("recording-", ".m4a");
        tempFile.deleteOnExit();
        assertTrue(tempFile.exists());

        setOutputFile(plugin, tempFile);
        setStatus(plugin, "INACTIVE");

        invokeCancelRecording(plugin, mock(PluginCall.class));

        assertTrue(tempFile.exists());
        assertNull(getOutputFile(plugin));
    }

    @Test
    public void cancelRecording_whenDiscarding_deletesOutputFile() throws Exception {
        CapacitorAudioRecorderPlugin plugin = new CapacitorAudioRecorderPlugin();
        File tempFile = File.createTempFile("recording-", ".m4a");
        assertTrue(tempFile.exists());

        setOutputFile(plugin, tempFile);
        setStatus(plugin, "RECORDING");

        invokeCancelRecording(plugin, mock(PluginCall.class));

        assertFalse(tempFile.exists());
        assertNull(getOutputFile(plugin));
    }

    private static void invokeCancelRecording(CapacitorAudioRecorderPlugin plugin, PluginCall call) throws Exception {
        plugin.cancelRecording(call);
    }

    private static void setOutputFile(CapacitorAudioRecorderPlugin plugin, File file) throws Exception {
        Field field = CapacitorAudioRecorderPlugin.class.getDeclaredField("outputFile");
        field.setAccessible(true);
        field.set(plugin, file);
    }

    private static File getOutputFile(CapacitorAudioRecorderPlugin plugin) throws Exception {
        Field field = CapacitorAudioRecorderPlugin.class.getDeclaredField("outputFile");
        field.setAccessible(true);
        return (File) field.get(plugin);
    }

    private static void setStatus(CapacitorAudioRecorderPlugin plugin, String statusName) throws Exception {
        Field field = CapacitorAudioRecorderPlugin.class.getDeclaredField("status");
        field.setAccessible(true);
        @SuppressWarnings("unchecked")
        Class<Enum<?>> statusClass = (Class<Enum<?>>) field.getType();
        for (Enum<?> value : statusClass.getEnumConstants()) {
            if (value.name().equals(statusName)) {
                field.set(plugin, value);
                return;
            }
        }
        throw new IllegalArgumentException("Unknown status: " + statusName);
    }

    private static void invokeReleaseRecorder(CapacitorAudioRecorderPlugin plugin) throws Exception {
        Method method = CapacitorAudioRecorderPlugin.class.getDeclaredMethod("releaseRecorder");
        method.setAccessible(true);
        method.invoke(plugin);
    }
}
