plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.toomu"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.toomu"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // youtubedl-android runs libpython.so / libffmpeg.so / libqjs.so as
    // executables, so native libs must be extracted to disk on install.
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    buildTypes {
        debug {
            // yt-dlp + Python + FFmpeg add ~49 MB per CPU type, so debug builds
            // only package 64-bit ARM (phones + Apple-silicon emulators).
            // Add "x86_64" here for Intel emulators.
            // Release builds: `flutter build apk --split-per-abi`.
            ndk {
                abiFilters += listOf("arm64-v8a")
            }
        }
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // yt-dlp (+ Python, QuickJS for YouTube's JS challenges) and its FFmpeg.
    // GPL-3.0. yt-dlp itself updates at runtime from GitHub releases.
    val youtubedlAndroid = "0.18.1"
    implementation("io.github.junkfood02.youtubedl-android:library:$youtubedlAndroid")
    implementation("io.github.junkfood02.youtubedl-android:ffmpeg:$youtubedlAndroid")
    // Multi-connection downloader for faster YouTube downloads (+~7 MB/ABI).
    implementation("io.github.junkfood02.youtubedl-android:aria2c:$youtubedlAndroid")
}
