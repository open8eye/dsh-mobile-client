package com.dshmobile.dsh_mobile_client

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri

/**
 * Runs [WebViewKernel.upgradeIfNeeded] at the only moment it can work.
 *
 * A ContentProvider's `onCreate` fires during `bindApplication` — after the
 * process exists but strictly before `Application.onCreate`, and therefore
 * before Flutter or any plugin can create a WebView. Once a WebView has been
 * created the provider is bound for the life of the process and cannot be
 * swapped, so this ordering is not a preference, it is the whole mechanism.
 *
 * The provider stores nothing and exposes nothing; it is a startup hook that
 * happens to be spelled `ContentProvider`.
 */
class WebViewKernelProvider : ContentProvider() {
    override fun onCreate(): Boolean {
        context?.let { WebViewKernel.upgradeIfNeeded(it) }
        return true
    }

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor? = null

    override fun getType(uri: Uri): String? = null

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int = 0
}
