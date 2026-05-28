plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.wranglv0"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.wranglv0"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            // Restrict to ARM64 — fllama's x86_64 native library crashes on
            // loadModelDetails when initLlamaContext returns 0 (OOM / emulator).
            // The 5 GB model requires a real ARM64 device with ≥8 GB RAM.
            abiFilters += listOf("arm64-v8a")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")

            // flutter_gemma bundles MediaPipe, which references optional protobuf
            // classes via reflection. R8/minification fails on (and can strip)
            // those, and APK shrinking is irrelevant next to the multi-GB model
            // download — so keep release unminified.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

dependencies {
    implementation("com.google.android.play:core:1.10.3")
    // If using newer split packages, uncomment the following lines instead:
    // implementation("com.google.android.play:core-common:2.0.3")
    // implementation("com.google.android.play:feature-delivery:2.1.0")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
