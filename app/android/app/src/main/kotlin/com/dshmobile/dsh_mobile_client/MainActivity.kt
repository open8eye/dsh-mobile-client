package com.dshmobile.dsh_mobile_client

import android.content.Intent
import android.content.pm.PackageInfo
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.webkit.WebView
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Hosts Flutter and exposes the few native capabilities Flutter cannot provide:
 * a window floating over other apps, and handing a downloaded APK to the
 * package installer.
 */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APP_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openAppSettings" -> {
                        result.success(openSystemScreen(Settings.ACTION_APPLICATION_DETAILS_SETTINGS))
                    }

                    "canInstallPackages" -> {
                        // Below Android 8 there is no per-app sideloading gate.
                        val allowed = Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                            packageManager.canRequestPackageInstalls()
                        result.success(allowed)
                    }

                    "requestInstallPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            openSystemScreen(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                        }
                        result.success(null)
                    }

                    "deviceInfo" -> result.success(deviceInfo())

                    // Which kernel the process actually bound to, and whether
                    // it had to be swapped. Reported on every diagnostics run.
                    "webViewKernel" -> result.success(WebViewKernel.outcome())

                    // Which build this is. The updater needs it: the legacy and
                    // standard APKs are different artefacts with different
                    // update paths, and crossing them breaks old devices.
                    "buildVariant" -> result.success(
                        if (WebViewKernel.bundledAsset(this) != null) "legacy" else "standard",
                    )

                    "openAppInfo" -> {
                        val target = call.argument<String>("package") ?: packageName
                        result.success(
                            openSystemScreen(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, target),
                        )
                    }

                    "shareText" -> {
                        val text = call.argument<String>("text")
                        if (text == null) {
                            result.error("bad_args", "shareText needs text", null)
                            return@setMethodCallHandler
                        }
                        val subject = call.argument<String>("subject") ?: getString(R.string.app_name)
                        try {
                            val send = Intent(Intent.ACTION_SEND).apply {
                                type = "text/plain"
                                putExtra(Intent.EXTRA_SUBJECT, subject)
                                putExtra(Intent.EXTRA_TEXT, text)
                            }
                            startActivity(
                                Intent.createChooser(send, subject)
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                            )
                            result.success(null)
                        } catch (error: Exception) {
                            result.error("share_failed", error.message, null)
                        }
                    }

                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("bad_args", "installApk needs a path", null)
                            return@setMethodCallHandler
                        }
                        try {
                            installApk(path)
                            result.success(null)
                        } catch (error: Exception) {
                            result.error("install_failed", error.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PET_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isSupported" -> result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)

                    "hasOverlayPermission" -> result.success(Settings.canDrawOverlays(this))

                    "requestOverlayPermission" -> {
                        val alreadyGranted = Settings.canDrawOverlays(this)
                        if (!alreadyGranted) {
                            // The system screen has no result callback, so the
                            // caller re-checks after the app resumes.
                            openSystemScreen(Settings.ACTION_MANAGE_OVERLAY_PERMISSION)
                        }
                        result.success(alreadyGranted)
                    }

                    "isVisible" -> result.success(PetOverlayService.isRunning)

                    "show" -> {
                        if (!Settings.canDrawOverlays(this)) {
                            result.success(false)
                        } else {
                            val intent = Intent(this, PetOverlayService::class.java).apply {
                                action = PetOverlayService.ACTION_SHOW
                                putExtra(PetOverlayService.EXTRA_SCALE, (call.argument<Double>("scale") ?: 1.0).toFloat())
                                putExtra(PetOverlayService.EXTRA_OPACITY, (call.argument<Double>("opacity") ?: 1.0).toFloat())
                                putExtra(PetOverlayService.EXTRA_IMAGE_PATH, call.argument<String>("imagePath"))
                            }
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(intent)
                            } else {
                                startService(intent)
                            }
                            result.success(true)
                        }
                    }

                    "hide" -> {
                        startService(
                            Intent(this, PetOverlayService::class.java).apply {
                                action = PetOverlayService.ACTION_HIDE
                            },
                        )
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Facts a bug report needs.
     *
     * The WebView package matters most. On some OEM builds — MIUI in particular
     * — the system WebView is missing, disabled or years out of date, and every
     * page then renders white with no error surfaced anywhere. Nothing inside
     * Dart can see that, so it has to be asked for here.
     */
    private fun deviceInfo(): Map<String, Any?> {
        val webView = webViewPackage()
        return linkedMapOf(
            "manufacturer" to Build.MANUFACTURER,
            "brand" to Build.BRAND,
            "model" to Build.MODEL,
            "device" to Build.DEVICE,
            "androidRelease" to Build.VERSION.RELEASE,
            "sdkInt" to Build.VERSION.SDK_INT,
            "supportedAbis" to Build.SUPPORTED_ABIS.joinToString(","),
            // OEM skins: MIUI only exposes its version as a system property, and
            // hidden-API restrictions can block reading it. The build strings
            // are a fallback that always works.
            "miui" to systemProperty("ro.miui.ui.version.name"),
            "buildDisplay" to Build.DISPLAY,
            "incremental" to Build.VERSION.INCREMENTAL,
            "webViewPackage" to (webView?.packageName ?: "missing"),
            "webViewVersion" to (webView?.versionName ?: "unknown"),
            // What the startup hook did, if anything. "not attempted" means the
            // process never ran it, which is itself worth seeing.
            "webViewKernel" to WebViewKernel.outcome(),
        )
    }

    @Suppress("DEPRECATION")
    private fun webViewPackage(): PackageInfo? {
        val current = runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WebView.getCurrentWebViewPackage()
            } else {
                null
            }
        }.getOrNull()
        if (current != null) return current

        // Below Android 8, or when the current provider cannot be resolved:
        // ask the known providers directly so "missing" can be told apart from
        // "unknown".
        val candidates = listOf(
            "com.google.android.webview",
            "com.android.webview",
            "com.google.android.webview.beta",
        )
        return candidates.firstNotNullOfOrNull { name ->
            runCatching { packageManager.getPackageInfo(name, 0) }.getOrNull()
        }
    }

    /** Read a build property; returns null when hidden-API rules block it. */
    private fun systemProperty(key: String): String? = runCatching {
        val clazz = Class.forName("android.os.SystemProperties")
        val get = clazz.getMethod("get", String::class.java)
        (get.invoke(null, key) as? String)?.takeIf { it.isNotBlank() }
    }.getOrNull()

    /**
     * Open a package's page in system settings.
     *
     * Defaults to this app; [target] lets it point at the system WebView, which
     * is the component an old device actually needs to update.
     */
    private fun openSystemScreen(action: String, target: String = packageName): Boolean {
        val intent = Intent(action, Uri.parse("package:$target"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return runCatching { startActivity(intent) }.isSuccess
    }

    /**
     * Hand a downloaded APK to the system installer.
     *
     * The file lives in the app's own cache, so it must travel as a content URI
     * through our FileProvider: passing a `file://` URI throws
     * FileUriExposedException on Android 7+.
     */
    private fun installApk(path: String) {
        val file = File(path)
        require(file.exists()) { "APK not found at $path" }

        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    private companion object {
        const val PET_CHANNEL = "com.dshmobile.dsh_mobile_client/pet"
        const val APP_CHANNEL = "com.dshmobile.dsh_mobile_client/app"
    }
}
