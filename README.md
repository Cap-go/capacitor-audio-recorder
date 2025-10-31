# @capgo/capacitor-audio-recorder
 <a href="https://capgo.app/"><img src='https://raw.githubusercontent.com/Cap-go/capgo/main/assets/capgo_banner.png' alt='Capgo - Instant updates for capacitor'/></a>

<div align="center">
  <h2><a href="https://capgo.app/?ref=plugin_audio_recorder"> ➡️ Get Instant updates for your App with Capgo</a></h2>
  <h2><a href="https://capgo.app/consulting/?ref=plugin_audio_recorder"> Missing a feature? We’ll build the plugin for you 💪</a></h2>
</div>


Capture audio clips across iOS, Android, and the Web with a consistent Capacitor API.

## Why Capacitor Audio Recorder?

The only **free** and **up-to-date** audio recording plugin for Capacitor:

- **Same JavaScript API** - Compatible interface with paid plugins
- **Full feature set** - Pause/resume, configurable bitrates, sample rates
- **Cross-platform** - iOS, Android, and Web support
- **Modern implementation** - Uses latest platform APIs
- **Event listeners** - Real-time recording status and error handling

Perfect for voice memo apps, audio messaging, podcast recording, and any app needing audio capture.

## Documentation

The most complete doc is available here: https://capgo.app/docs/plugins/audio-recorder/

## Install

```bash
npm install @capgo/capacitor-audio-recorder
npx cap sync
```

## API

<docgen-index>

* [`startRecording(...)`](#startrecording)
* [`pauseRecording()`](#pauserecording)
* [`resumeRecording()`](#resumerecording)
* [`stopRecording()`](#stoprecording)
* [`cancelRecording()`](#cancelrecording)
* [`getRecordingStatus()`](#getrecordingstatus)
* [`checkPermissions()`](#checkpermissions)
* [`requestPermissions()`](#requestpermissions)
* [`addListener('recordingError', ...)`](#addlistenerrecordingerror-)
* [`addListener('recordingPaused', ...)`](#addlistenerrecordingpaused-)
* [`addListener('recordingStopped', ...)`](#addlistenerrecordingstopped-)
* [`removeAllListeners()`](#removealllisteners)
* [`getPluginVersion()`](#getpluginversion)
* [Interfaces](#interfaces)
* [Type Aliases](#type-aliases)
* [Enums](#enums)

</docgen-index>

<docgen-api>
<!--Update the source file JSDoc comments and rerun docgen to update the docs below-->

Capacitor plugin contract for recording audio.

### startRecording(...)

```typescript
startRecording(options?: StartRecordingOptions | undefined) => Promise<void>
```

Start recording audio using the device microphone.

| Param         | Type                                                                    | Description                      |
| ------------- | ----------------------------------------------------------------------- | -------------------------------- |
| **`options`** | <code><a href="#startrecordingoptions">StartRecordingOptions</a></code> | Recording configuration options. |

**Since:** 1.0.0

--------------------


### pauseRecording()

```typescript
pauseRecording() => Promise<void>
```

Pause the ongoing recording. Only available on Android (API 24+), iOS, and Web.

**Since:** 1.0.0

--------------------


### resumeRecording()

```typescript
resumeRecording() => Promise<void>
```

Resume a previously paused recording.

**Since:** 1.0.0

--------------------


### stopRecording()

```typescript
stopRecording() => Promise<StopRecordingResult>
```

Stop the current recording and persist the recorded audio.

**Returns:** <code>Promise&lt;<a href="#stoprecordingresult">StopRecordingResult</a>&gt;</code>

**Since:** 1.0.0

--------------------


### cancelRecording()

```typescript
cancelRecording() => Promise<void>
```

Cancel the current recording and discard any captured audio.

**Since:** 1.0.0

--------------------


### getRecordingStatus()

```typescript
getRecordingStatus() => Promise<GetRecordingStatusResult>
```

Retrieve the current recording status.

**Returns:** <code>Promise&lt;<a href="#getrecordingstatusresult">GetRecordingStatusResult</a>&gt;</code>

**Since:** 1.0.0

--------------------


### checkPermissions()

```typescript
checkPermissions() => Promise<PermissionStatus>
```

Return the current permission state for accessing the microphone.

**Returns:** <code>Promise&lt;<a href="#permissionstatus">PermissionStatus</a>&gt;</code>

**Since:** 1.0.0

--------------------


### requestPermissions()

```typescript
requestPermissions() => Promise<PermissionStatus>
```

Request permission to access the microphone.

**Returns:** <code>Promise&lt;<a href="#permissionstatus">PermissionStatus</a>&gt;</code>

**Since:** 1.0.0

--------------------


### addListener('recordingError', ...)

```typescript
addListener(eventName: 'recordingError', listenerFunc: (event: RecordingErrorEvent) => void) => Promise<PluginListenerHandle>
```

Listen for recording errors.

| Param              | Type                                                                                    |
| ------------------ | --------------------------------------------------------------------------------------- |
| **`eventName`**    | <code>'recordingError'</code>                                                           |
| **`listenerFunc`** | <code>(event: <a href="#recordingerrorevent">RecordingErrorEvent</a>) =&gt; void</code> |

**Returns:** <code>Promise&lt;<a href="#pluginlistenerhandle">PluginListenerHandle</a>&gt;</code>

**Since:** 1.0.0

--------------------


### addListener('recordingPaused', ...)

```typescript
addListener(eventName: 'recordingPaused', listenerFunc: () => void) => Promise<PluginListenerHandle>
```

Listen for pause events emitted when a recording is paused.

| Param              | Type                           |
| ------------------ | ------------------------------ |
| **`eventName`**    | <code>'recordingPaused'</code> |
| **`listenerFunc`** | <code>() =&gt; void</code>     |

**Returns:** <code>Promise&lt;<a href="#pluginlistenerhandle">PluginListenerHandle</a>&gt;</code>

**Since:** 1.0.0

--------------------


### addListener('recordingStopped', ...)

```typescript
addListener(eventName: 'recordingStopped', listenerFunc: (event: RecordingStoppedEvent) => void) => Promise<PluginListenerHandle>
```

Listen for recording completion events.

| Param              | Type                                                                                    |
| ------------------ | --------------------------------------------------------------------------------------- |
| **`eventName`**    | <code>'recordingStopped'</code>                                                         |
| **`listenerFunc`** | <code>(event: <a href="#stoprecordingresult">StopRecordingResult</a>) =&gt; void</code> |

**Returns:** <code>Promise&lt;<a href="#pluginlistenerhandle">PluginListenerHandle</a>&gt;</code>

**Since:** 1.0.0

--------------------


### removeAllListeners()

```typescript
removeAllListeners() => Promise<void>
```

Remove all registered listeners.

**Since:** 1.0.0

--------------------


### getPluginVersion()

```typescript
getPluginVersion() => Promise<{ version: string; }>
```

Get the native Capacitor plugin version.

**Returns:** <code>Promise&lt;{ version: string; }&gt;</code>

**Since:** 1.0.0

--------------------


### Interfaces


#### StartRecordingOptions

Options accepted by {@link CapacitorAudioRecorderPlugin.startRecording}.

| Prop                              | Type                                                          | Description                                                                | Since |
| --------------------------------- | ------------------------------------------------------------- | -------------------------------------------------------------------------- | ----- |
| **`audioSessionCategoryOptions`** | <code>AudioSessionCategoryOption[]</code>                     | The audio session category options for recording. Only available on iOS.   | 1.0.0 |
| **`audioSessionMode`**            | <code><a href="#audiosessionmode">AudioSessionMode</a></code> | The audio session mode for recording. Only available on iOS.               | 1.0.0 |
| **`bitRate`**                     | <code>number</code>                                           | The audio bit rate in bytes per second. Only available on Android and iOS. | 1.0.0 |
| **`sampleRate`**                  | <code>number</code>                                           | The audio sample rate in Hz. Only available on Android and iOS.            | 1.0.0 |


#### StopRecordingResult

Result returned by {@link CapacitorAudioRecorderPlugin.stopRecording}.

| Prop           | Type                | Description                                                               | Since |
| -------------- | ------------------- | ------------------------------------------------------------------------- | ----- |
| **`blob`**     | <code>Blob</code>   | The recorded audio as a Blob. Only available on Web.                      | 1.0.0 |
| **`duration`** | <code>number</code> | The duration of the recording in milliseconds.                            | 1.0.0 |
| **`uri`**      | <code>string</code> | The URI pointing to the recorded file. Only available on Android and iOS. | 1.0.0 |


#### GetRecordingStatusResult

Result returned by {@link CapacitorAudioRecorderPlugin.getRecordingStatus}.

| Prop         | Type                                                        | Description                   | Since |
| ------------ | ----------------------------------------------------------- | ----------------------------- | ----- |
| **`status`** | <code><a href="#recordingstatus">RecordingStatus</a></code> | The current recording status. | 1.0.0 |


#### PermissionStatus

Permission information returned by {@link CapacitorAudioRecorderPlugin.checkPermissions}
and {@link CapacitorAudioRecorderPlugin.requestPermissions}.

| Prop              | Type                                                        | Description                               | Since |
| ----------------- | ----------------------------------------------------------- | ----------------------------------------- | ----- |
| **`recordAudio`** | <code><a href="#permissionstate">PermissionState</a></code> | The permission state for audio recording. | 1.0.0 |


#### PluginListenerHandle

| Prop         | Type                                      |
| ------------ | ----------------------------------------- |
| **`remove`** | <code>() =&gt; Promise&lt;void&gt;</code> |


#### RecordingErrorEvent

Event emitted when an error occurs during recording.

| Prop          | Type                | Description        | Since |
| ------------- | ------------------- | ------------------ | ----- |
| **`message`** | <code>string</code> | The error message. | 1.0.0 |


### Type Aliases


#### PermissionState

<code>'prompt' | 'prompt-with-rationale' | 'granted' | 'denied'</code>


#### RecordingStoppedEvent

Event emitted when a recording completes.

<code><a href="#stoprecordingresult">StopRecordingResult</a></code>


### Enums


#### AudioSessionCategoryOption

| Members                                    | Value                                                     |
| ------------------------------------------ | --------------------------------------------------------- |
| **`AllowAirPlay`**                         | <code>'ALLOW_AIR_PLAY'</code>                             |
| **`AllowBluetooth`**                       | <code>'ALLOW_BLUETOOTH'</code>                            |
| **`AllowBluetoothA2DP`**                   | <code>'ALLOW_BLUETOOTH_A2DP'</code>                       |
| **`DefaultToSpeaker`**                     | <code>'DEFAULT_TO_SPEAKER'</code>                         |
| **`DuckOthers`**                           | <code>'DUCK_OTHERS'</code>                                |
| **`InterruptSpokenAudioAndMixWithOthers`** | <code>'INTERRUPT_SPOKEN_AUDIO_AND_MIX_WITH_OTHERS'</code> |
| **`MixWithOthers`**                        | <code>'MIX_WITH_OTHERS'</code>                            |
| **`OverrideMutedMicrophoneInterruption`**  | <code>'OVERRIDE_MUTED_MICROPHONE_INTERRUPTION'</code>     |


#### AudioSessionMode

| Members              | Value                          |
| -------------------- | ------------------------------ |
| **`Default`**        | <code>'DEFAULT'</code>         |
| **`GameChat`**       | <code>'GAME_CHAT'</code>       |
| **`Measurement`**    | <code>'MEASUREMENT'</code>     |
| **`SpokenAudio`**    | <code>'SPOKEN_AUDIO'</code>    |
| **`VideoChat`**      | <code>'VIDEO_CHAT'</code>      |
| **`VideoRecording`** | <code>'VIDEO_RECORDING'</code> |
| **`VoiceChat`**      | <code>'VOICE_CHAT'</code>      |


#### RecordingStatus

| Members         | Value                    |
| --------------- | ------------------------ |
| **`Inactive`**  | <code>'INACTIVE'</code>  |
| **`Recording`** | <code>'RECORDING'</code> |
| **`Paused`**    | <code>'PAUSED'</code>    |

</docgen-api>

### Credit

This plugin was inspired from: https://github.com/kesha-antonov/react-native-background-downloader
