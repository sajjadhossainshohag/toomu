import java.util.Properties

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

    // Release key: android/key.properties (local) or the CI secrets
    // (ANDROID_KEYSTORE_PATH / _PASSWORD, ANDROID_KEY_ALIAS / _PASSWORD).
    // Without one, release builds use the debug key (fine for testing; but
    // phones only update an app signed with the same key).
    val keyProps = Properties().apply {
        val f = rootProject.file("key.properties")
        if (f.exists()) f.inputStream().use { load(it) }
    }
    fun signing(name: String, env: String): String? = keyProps.getProperty(name) ?: System.getenv(env)
    val releaseStore = signing("storeFile", "ANDROID_KEYSTORE_PATH")
    signingConfigs {
        if (releaseStore != null && file(releaseStore).exists()) {
            create("release") {
                storeFile = file(releaseStore)
                storePassword = signing("storePassword", "ANDROID_KEYSTORE_PASSWORD")
                keyAlias = signing("keyAlias", "ANDROID_KEY_ALIAS")
                keyPassword = signing("keyPassword", "ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        debug {
            // yt-dlp + Python + FFmpeg add ~49 MB per CPU type, so debug builds
            // only package 64-bit ARM (phones + Apple-silicon emulators).
            // Add "x86_64" here for Intel emulators. Not with
            // `--split-per-abi`, which picks the CPU types itself (and the
            // Android plugin refuses both at once).
            if (!project.hasProperty("split-per-abi")) {
                ndk {
                    abiFilters += listOf("arm64-v8a")
                }
            }
        }
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

// Smaller app: yt-dlp's bundled Python / FFmpeg / aria2c archives carry files
// nothing ever loads (a static QuickJS library, test modules, unused codecs'
// helper libraries…): ~8 MB per CPU type. tool/trim_ytdlp_bundles.py removes
// them right after the native libraries are merged, keeping everything any
// program or library the app runs links to. Without python3 the build goes
// on untrimmed.
tasks.configureEach {
    if (name.startsWith("merge") && name.endsWith("NativeLibs")) {
        // A changed trimming script re-runs the merge (fresh archives).
        inputs.file(project.file("../../tool/trim_ytdlp_bundles.py")).optional()
        doLast {
            val dirs = outputs.files.files.filter { it.isDirectory }.map { it.absolutePath }
            val script = project.file("../../tool/trim_ytdlp_bundles.py")
            if (dirs.isEmpty() || !script.exists()) return@doLast
            try {
                val process = ProcessBuilder(listOf("python3", "-I", script.absolutePath) + dirs)
                    .redirectErrorStream(true)
                    .start()
                val output = process.inputStream.bufferedReader().readText()
                if (process.waitFor() == 0) {
                    logger.lifecycle(output.trim())
                } else {
                    logger.warn("trim_ytdlp_bundles failed, archives left as they were:\n$output")
                }
            } catch (e: Exception) {
                logger.warn("trim_ytdlp_bundles skipped (python3 not found?): ${e.message}")
            }
        }
    }
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
