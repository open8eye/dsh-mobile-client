plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.dshmobile.dsh_mobile_client"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by flutter_local_notifications, which uses java.time on
        // API levels that predate it.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.dshmobile.dsh_mobile_client"
        // 24 covers the plugins in use (mobile_scanner, flutter_secure_storage,
        // flutter_inappwebview) and adaptive icons without legacy fallbacks.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Signed with the debug key so `flutter build apk --release` works
            // out of the box. Replace this with a real signing config before
            // publishing; the README explains how.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // Reuse a newer WebView kernel that is already installed, for this process
    // only, without touching the system WebView. MIT licensed; it hooks the
    // provider binders, which is why it must run from a ContentProvider.
    implementation("io.github.jonanorman.android.webviewup:core:0.1.0")
}

flutter {
    source = "../.."
}
