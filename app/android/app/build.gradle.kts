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

    // The bundled WebView kernel is deliberately NOT in noCompress.
    //
    // The first instinct is that deflating it saves nothing, because the
    // kernel is itself a zip. It is wrong: the kernel's own entries are mostly
    // *stored* (native libraries, dex), so it deflates well — 88.7 MB becomes
    // 47.1 MB. That is the difference between the legacy build fitting a
    // 100 MB upload limit and not fitting it at all.
    //
    // The cost is that unpacking it inflates instead of copying. That happens
    // once per install, on the provider's thread, and the result is cached on
    // disk afterwards — see WebViewKernel.bundledKernelFile.

    // Two builds from one codebase.
    //
    // `standard` is the normal app: the system WebView, upgraded in-process to
    // a newer kernel that happens to be installed.
    //
    // `legacy` carries its own kernel in assets/, so it works on a device with
    // nothing newer installed and asks the user for nothing at all. The kernel
    // is AOSP arm32 and the app is built 32-bit to match it — a 32-bit process
    // runs fine on 64-bit hardware, and the arm32 kernel is less than half the
    // size of the arm64 one.
    flavorDimensions += "engine"
    productFlavors {
        create("standard") { dimension = "engine" }
        create("legacy") { dimension = "engine" }
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

// The legacy build has to run as a 32-bit process: its bundled kernel is arm32,
// and a process cannot load a kernel built for the other width. Android chooses
// the process ABI from the native libraries in the APK, so a stray arm64 library
// from a plugin's AAR is enough to make the app start 64-bit — and then fail to
// find a 64-bit Flutter engine that was never built. Dropping the other ABIs makes
// the choice unambiguous, and saves a few megabytes besides.
androidComponents {
    onVariants(selector().withFlavor("engine", "legacy")) { variant ->
        variant.packaging.jniLibs.excludes.addAll(
            "**/arm64-v8a/**",
            "**/x86_64/**",
            "**/x86/**",
        )
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
