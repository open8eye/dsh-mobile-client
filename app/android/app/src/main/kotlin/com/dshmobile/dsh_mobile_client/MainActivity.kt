package com.dshmobile.dsh_mobile_client

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
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

    /** Open one of this app's pages in system settings. */
    private fun openSystemScreen(action: String): Boolean {
        val intent = Intent(action, Uri.parse("package:$packageName"))
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
