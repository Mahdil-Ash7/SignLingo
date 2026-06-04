# Suppress warnings for missing JDK-only classes used by code generators
-dontwarn javax.lang.model.**
-dontwarn autovalue.shaded.**

# If the error persists with specific AutoValue mentions, add this:
-dontwarn com.google.auto.value.**

# 1. MediaPipe Core
-keep class com.google.mediapipe.** { *; }
-dontwarn com.google.mediapipe.**

# 2. Protobuf (Used heavily for AI models)
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.protobuf.**

# 3. AutoValue (Used for MediaPipe data classes)
-keep class com.google.auto.value.** { *; }
-dontwarn com.google.auto.value.**

# 4. Guava and Flogger (Internal logging/utilities)
-keep class com.google.common.** { *; }
-dontwarn com.google.common.**
-keep class com.google.flogger.** { *; }
-dontwarn com.google.flogger.**

# 5. Ignore Unsafe warnings (common in low-level AI processing)
-dontwarn sun.misc.Unsafe
-dontwarn java.lang.invoke.**

# 6. Keep all JNI (C++) native methods intact
-keepclasseswithmembernames class * {
    native <methods>;
}