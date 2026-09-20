package com.dshmobile.dsh_mobile_client

import android.content.Context
import android.os.Build
import android.os.Process
import android.util.Log
import android.webkit.WebView
import com.norman.webviewup.lib.WebViewUpgrade
import com.norman.webviewup.lib.source.UpgradeFileSource
import com.norman.webviewup.lib.source.UpgradePackageSource
import java.io.File
import java.io.FileOutputStream

/**
 * Point this app at a newer WebView kernel than the one the system is stuck on.
 *
 * A device whose system WebView predates Chromium [MIN_CHROMIUM] cannot even
 * parse the DSH bundle, so the page stays white and no amount of injected
 * shimming helps. The fix is a newer engine, and there are three ways to get
 * one: reuse one already installed on the phone, ship one inside the APK, or
 * rewrite the browser layer against an entirely different engine. The third
 * costs tens of megabytes and a full rewrite; this file does the first two,
 * cheapest first.
 *
 * [WebViewUpgrade] hooks the WebView provider binders so
 * that **this process only** resolves its WebView from somewhere else. It does
 * not replace the system WebView, does not affect any other app, and needs no
 * root. A reused kernel is undone by uninstalling that kernel app; a bundled
 * one is undone by uninstalling this app.
 *
 * Two constraints shape the code below:
 *
 *  - The provider is bound the first time a WebView is created in the process,
 *    and cannot be swapped afterwards. So this must run before that — which is
 *    why it is driven from [WebViewKernelProvider] rather than from an Activity,
 *    and why a bundled kernel is unpacked there rather than lazily.
 *  - Only a **monolithic** kernel APK works. The split APKs Google Play
 *    delivers for Chrome and Android System WebView cannot be used as a kernel
 *    source, so a Play-installed Chrome will not be picked up even when it is
 *    new enough. Everything here degrades to "leave the system WebView alone".
 *
 * Note for whoever touches the release build type: the library reaches into
 * system internals by reflection, and R8 is on, so
 * `app/proguard-rules.pro` keeps `com.norman.webviewup.**` intact. Without it
 * R8 strips the hooks and the upgrade silently does nothing.
 */
object WebViewKernel {
    private const val TAG = "DshWebViewKernel"

    /**
     * The oldest Chromium that can parse the DSH bundle.
     *
     * Kept in step with `CompatScript.minimumChromium` on the Dart side: the
     * bundle uses `static {}` initialisation blocks, which need Chromium 94.
     * A test asserts the two numbers agree.
     */
    const val MIN_CHROMIUM = 94

    /**
     * Packages that can serve as a kernel, most preferred first.
     *
     * Stable Google WebView first, then progressively less stable channels as
     * fallbacks for devices where the stable channel is also pinned, and Chrome
     * last — it is a full browser rather than a WebView build, and Play's copy
     * is a split install that cannot be used at all.
     */
    private val CANDIDATES = listOf(
        "com.google.android.webview",
        "com.google.android.webview.beta",
        "com.google.android.webview.dev",
        "com.google.android.webview.canary",
        "com.android.chrome",
    )

    /** Human-readable result, surfaced in the app's diagnostics report. */
    @Volatile
    private var outcome: String = "not attempted"

    /**
     * The same result, plus which kernel the process ended up on.
     *
     * "We asked for a kernel" and "we got one" are different states, and the
     * difference decides whether a white screen is the old engine or a hook
     * that never took. The library knows the answer once it has replaced the
     * provider, so it is appended here rather than guessed at.
     */
    fun outcome(): String {
        val effective = WebViewUpgrade.getUpgradeWebViewVersion()
        if (!effective.isNullOrEmpty()) return "$outcome (now $effective)"
        val error = WebViewUpgrade.getUpgradeError()
        if (error != null) {
            return "$outcome (failed: ${error.javaClass.simpleName}: ${error.message})"
        }
        return outcome
    }

    /** Chromium major behind a version string like `83.0.4103.101`. */
    fun chromiumMajor(version: String?): Int? =
        version?.trim()?.takeWhile { it.isDigit() }?.takeIf { it.isNotEmpty() }?.toIntOrNull()

    /**
     * Put this process on a newer kernel, if this build has one or the phone
     * has one and the system WebView is too old.
     *
     * Never throws: a device we cannot upgrade must still boot and must still
     * show the app's own explanation screen.
     */
    fun upgradeIfNeeded(context: Context) {
        try {
            // A kernel shipped inside this build comes first, and is decided
            // from the asset alone: nothing on this path asks WebView anything.
            // The library refuses to act once the process has bound a provider,
            // and it is cheaper to be certainly early than to reason about what
            // an early query might cache on the way.
            val bundled = bundledAsset(context)
            if (bundled != null) {
                val kernel = bundledKernelFile(context, bundled)
                if (kernel == null) {
                    outcome = "bundled kernel could not be unpacked: $bundled"
                } else {
                    WebViewUpgrade.upgrade(UpgradeFileSource(context, kernel))
                    outcome = "upgraded kernel: bundled $bundled"
                }
                Log.i(TAG, outcome)
                return
            }

            val system = WebView.getCurrentWebViewPackage()
            val systemName = system?.packageName ?: "unknown"
            val systemVersion = system?.versionName
            val systemMajor = chromiumMajor(systemVersion)

            if (systemMajor != null && systemMajor >= MIN_CHROMIUM) {
                outcome = "system kernel is current: $systemName $systemVersion"
                Log.i(TAG, outcome)
                return
            }

            // Pick the best installed candidate. A candidate that is not newer
            // than what the system already has would be a downgrade or a no-op.
            var best: Pair<String, Int>? = null
            for (name in CANDIDATES) {
                val major = installedMajor(context, name) ?: continue
                if (major < MIN_CHROMIUM) continue
                if (systemMajor != null && major <= systemMajor) continue
                best = name to major
                break
            }

            val chosen = best
            if (chosen == null) {
                outcome = "no newer kernel installed (system: $systemName $systemVersion); " +
                    "user must install a monolithic WebView or Chrome APK"
                Log.w(TAG, outcome)
                return
            }

            val (name, major) = chosen
            WebViewUpgrade.upgrade(UpgradePackageSource(context, name))
            outcome = "upgraded kernel: $systemName $systemVersion -> $name (Chromium $major)"
            Log.i(TAG, outcome)
        } catch (t: Throwable) {
            outcome = "kernel upgrade failed: ${t.javaClass.simpleName}: ${t.message}"
            Log.w(TAG, outcome, t)
        }
    }

    /** The 64-bit ABIs, so the ABI list can be split without guessing. */
    private val ABI_64 = setOf("arm64-v8a", "x86_64", "mips64", "riscv64")

    /**
     * ABIs to look for a bundled kernel under, best first.
     *
     * `Build.SUPPORTED_ABIS` describes the *device*, not this process: a 32-bit
     * process on a 64-bit phone reports arm64-v8a first, and an arm64 kernel
     * cannot be loaded into it. The legacy build pairs a 32-bit app with a
     * 32-bit kernel, so the half of the list that matches the process is tried
     * first and the rest is kept only as a fallback.
     */
    private fun abiCandidates(): List<String> {
        val supported = Build.SUPPORTED_ABIS?.toList().orEmpty()
        val processIs64 = Process.is64Bit()
        return (supported.filter { (it in ABI_64) == processIs64 } + supported).distinct()
    }

    /**
     * Asset path of a kernel bundled with this build, or null if there is none.
     *
     * Also the app's own definition of "this is the legacy build": the flavour
     * is not otherwise visible at runtime, and a build that carries a kernel is
     * exactly what makes it legacy.
     */
    fun bundledAsset(context: Context): String? =
        abiCandidates()
            .map { "webview/$it.apk" }
            .firstOrNull { hasAsset(context, it) }

    private fun hasAsset(context: Context, name: String): Boolean = try {
        context.assets.open(name).close()
        true
    } catch (e: Exception) {
        false
    }

    /**
     * The bundled kernel as a file on disk, unpacked from assets on first use.
     *
     * Deliberately not the library's own `UpgradeAssetSource`: that one re-copies
     * the asset on every launch, on a thread of its own, which leaves a window
     * in which the session's first WebView is still created against the old
     * system kernel — and that bind cannot be taken back once it happens.
     * Copying here, on the provider's thread, means the kernel is in place
     * before anything in the process can ask for a WebView.
     *
     * The name carries the install time so that an app update never reuses the
     * kernel the previous version unpacked.
     */
    private fun bundledKernelFile(context: Context, asset: String): File? {
        val dir = kernelDir(context)
        val name = asset.substringAfterLast('/').removeSuffix(".apk")
        val target = File(dir, "$name-${installStamp(context)}.apk")
        // Anything else in here came from an older install of the app.
        dir.listFiles()?.forEach { if (it.absolutePath != target.absolutePath) it.delete() }
        if (target.length() > 0) return target
        return try {
            context.assets.open(asset).use { input ->
                FileOutputStream(target).use { output -> input.copyTo(output) }
            }
            if (target.length() > 0) target else null
        } catch (e: Exception) {
            Log.w(TAG, "could not unpack " + asset, e)
            target.delete()
            null
        }
    }

    /** Changes on every install and update, so it identifies the APK's contents. */
    @Suppress("DEPRECATION")
    private fun installStamp(context: Context): Long = try {
        context.packageManager.getPackageInfo(context.packageName, 0).lastUpdateTime
    } catch (e: Exception) {
        0L
    }

    /** Where a bundled kernel is unpacked. Persisted so it is extracted once. */
    private fun kernelDir(context: Context): File =
        File(context.filesDir, "webview-kernel").apply { mkdirs() }

    /** Chromium major of an installed package, or null when absent/unreadable. */
    @Suppress("DEPRECATION")
    private fun installedMajor(context: Context, packageName: String): Int? = try {
        chromiumMajor(context.packageManager.getPackageInfo(packageName, 0).versionName)
    } catch (e: Exception) {
        null
    }
}
