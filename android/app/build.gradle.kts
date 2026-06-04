plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.SignLingo"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.SignLingo"
        minSdk = 24   // MediaPipe Tasks requires API 24+ (was flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // ADD THIS TO ENSURE NDK COMPATIBILITY
        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a", "x86", "x86_64")
                }
    }

buildTypes {
    getByName("release") {
        // 1. Enabling R8/ProGuard features
        isMinifyEnabled = true
        isShrinkResources = true
        
        // 2. Linking your custom rules file
        proguardFiles(
            getDefaultProguardFile("proguard-android-optimize.txt"),
            "proguard-rules.pro"
        )
        
        // 3. Signing configuration
        // Change "release" back to "debug" if you haven't created a release keystore yet
        signingConfig = signingConfigs.getByName("debug")
    }
}

    aaptOptions {
        noCompress("tflite", "task")
    }
}

flutter {
    source = "../.."
}

dependencies {
    // MediaPipe Tasks Vision — provides HolisticLandmarker for on-device keypoint extraction
    implementation("com.google.mediapipe:tasks-vision:0.10.14")   

    // CameraX
    val cameraxVersion = "1.3.1"

    implementation("androidx.camera:camera-core:$cameraxVersion")
    implementation("androidx.camera:camera-camera2:$cameraxVersion")
    implementation("androidx.camera:camera-lifecycle:$cameraxVersion")
}

configurations.all {
    resolutionStrategy {
        force("com.google.mediapipe:tasks-vision:0.10.26.1")
    }
}

configurations.all {
    exclude(group = "com.google.mediapipe", module = "tasks-vision-image-generator")
}