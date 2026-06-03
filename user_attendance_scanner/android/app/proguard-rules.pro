# ZKFinger SDK and MethodChannel preservation
-keep class com.example.user_attendance_scanner.** { *; }
-keepclasseswithmembernames class * { native <methods>; }

# Preserve MethodChannel handlers
-keep class * extends android.os.Handler { *; }
-keep class android.os.Handler { *; }

# Preserve native method references
-keepclasseswithmembers class * {
    native <methods>;
}

# Preserve all classes that might be called from Flutter/Dart
-keep class * extends android.app.Service { *; }
-keep class * extends android.content.BroadcastReceiver { *; }

# ZKFinger library preservation - comprehensive
-keep class com.zk.** { *; }
-keep class com.zkteco.** { *; }
-keepclassmembers class com.zk.** { *; }
-keepclassmembers class com.zkteco.** { *; }
-keep class com.example.user_attendance_scanner.ZKTecoUSB { *; }

# Preserve ZKFinger method signatures
-keepclassmembers class * {
    *** acquire*(...);
    *** capture*(...);
    *** match*(...);
    *** identify*(...);
    *** enroll*(...);
    *** verify*(...);
    *** init*(...);
    *** open*(...);
    *** close*(...);
}

# USB communication
-keep class android.hardware.usb.** { *; }
-keep class com.android.internal.usb.** { *; }

# Preserve all public constructors for reflection
-keepclasseswithmembers class * {
    public <init>(...);
}

# Preserve all methods that might be called via reflection
-keepclasseswithmembers class * {
    public <methods>;
}

# R8 optimizations - be conservative
-optimizationpasses 5
-dontusemixedcaseclassnames
-dontwarn com.zk.**
-dontwarn com.zkteco.**
