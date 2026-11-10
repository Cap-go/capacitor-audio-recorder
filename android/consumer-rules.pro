# Consumer rules for @capgo/capacitor-audio-recorder (merged into apps that depend on this AAR).
# R8 runs in app release builds. Capacitor loads plugins by class and invokes @PluginMethod
# and permission callbacks by reflection.

# Keep the CapacitorAudioRecorderPlugin type and members so the bridge can instantiate it and invoke methods.
-keep class app.capgo.audiorecorder.CapacitorAudioRecorderPlugin { *; }

# Keep methods Capacitor calls reflectively on Plugin subclasses across the app (this plugin and similar).
-keepclassmembers class * extends com.getcapacitor.Plugin {
    @com.getcapacitor.annotation.PermissionCallback *;
    @com.getcapacitor.PluginMethod *;
}

# Keep annotation names and generic signatures Capacitor may read when wiring the plugin.
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes Exceptions
