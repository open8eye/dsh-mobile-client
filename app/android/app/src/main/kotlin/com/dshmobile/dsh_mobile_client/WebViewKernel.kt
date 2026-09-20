package com.dshmobile.dsh_mobile_client

import android.content.Context
import android.util.Log
import android.webkit.WebView
import com.norman.webviewup.lib.WebViewUpgrade
import com.norman.webviewup.lib.source.UpgradePackageSource

/**
 * Point this app at a newer WebView kernel than the one the system is stuck on.
 *
 * A device whose system WebView predates Chromium [MIN_CHROMIUM] cannot even
 * parse the DSH bundle, so the page stays white and no amount of injected
 * shimming helps. The fix is a newer engine, and there are two ways to get one:
 * ship one (tens of megabytes, and a browser layer to rewrite), or reuse one
 * that is already on the phone.
 *
 * This does the latter. [WebViewUpgrade] hooks the WebView provider binders so
 * that **this process only** resolves its WebView from another installed
 * package. It does not replace the system WebView, does not affect any other
 * app, and needs no root. The user can undo it by uninstalling the kernel app.
 *
 * Two constraints shape the code below:
 *
 *  - The provider is bound the first time a WebView is created in the process,
 *    and cannot be swapped afterwards. So this must run before that — which is
 *    why it is driven from [WebViewKernelProvider] rather than from an Activity.
 *  - Only a **monolithic** kernel APK works. The split APKs Google Play
 *    delivers for Chrome and Android System WebView cannot be used as a kernel
 *    source, so a Play-installed Chrome will not be picked up even when it is
 *    new enough. Everything here degrades to "leave the system WebView alone".
 *
 * Note for whoever turns on R8: the library reaches into system internals by
 * reflection, so minification must keep `com.norman.webviewup.**` intact. The
 * release build does not minify today, which is why no rule is needed yet.
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

    fun outcome(): String = outcome

    /** Chromium major behind a version string like `83.0.4103.101`. */
    fun chromiumMajor(version: String?): Int? =
        version?.trim()?.takeWhile { it.isDigit() }?.takeIf { it.isNotEmpty() }?.toIntOrNull()

    /**
     * Swap in a newer kernel if one is installed and the system one is too old.
     *
     * Never throws: a device we cannot upgrade must still boot and must still
     * show the app's own explanation screen.
     */
    fun upgradeIfNeeded(context: Context) {
        try {
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

    /** Chromium major of an installed package, or null when absent/unreadable. */
    @Suppress("DEPRECATION")
    private fun installedMajor(context: Context, packageName: String): Int? = try {
        chromiumMajor(context.packageManager.getPackageInfo(packageName, 0).versionName)
    } catch (e: Exception) {
        null
    }
}
