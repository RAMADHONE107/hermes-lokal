package com.hermesagent.hermes_android

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File

/** Mirrors engine state + log into public Downloads so it can be inspected
 * without root, adb, or a working method channel.
 *
 * The MediaStore URI is resolved once and reused. Deleting and re-inserting the
 * row on every write used to cost a full MediaStore transaction per 16 KB tar
 * chunk, which throttled extraction to a few KB/s and made the file briefly
 * disappear (0 bytes) for readers. */
object Diagnostics {
    // Unique per app: the other Hermes package also writes
    // "hermes-engine-debug.txt", and MediaStore rows are owned per package.
    // Sharing a display name made openOutputStream hit a foreign row and fail.
    private const val NAME = "hermes-lokal-engine-debug.txt"

    @Volatile
    private var cachedUri: Uri? = null

    fun write(context: Context, text: String) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val uri = cachedUri ?: findOrCreate(context).also { cachedUri = it } ?: return
                // "wt" = write + truncate. Keeps the row and the path stable.
                context.contentResolver.openOutputStream(uri, "wt")?.use { out ->
                    out.write(text.toByteArray(Charsets.UTF_8))
                }
            } else {
                @Suppress("DEPRECATION")
                val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                File(dir, NAME).writeText(text)
            }
        } catch (_: Exception) {
            // A stale URI can happen after a reinstall or MediaStore reset.
            cachedUri = null
        }
    }

    private fun findOrCreate(context: Context): Uri? {
        val resolver = context.contentResolver
        val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
        resolver.query(
            collection,
            arrayOf(MediaStore.Downloads._ID),
            "${MediaStore.Downloads.DISPLAY_NAME}=? AND owner_package_name=?",
            arrayOf(NAME, context.packageName),
            null,
        )?.use { cursor ->
            if (cursor.moveToNext()) {
                return Uri.withAppendedPath(collection, cursor.getLong(0).toString())
            }
        }
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, NAME)
            put(MediaStore.Downloads.MIME_TYPE, "text/plain")
            put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/hermes")
        }
        return resolver.insert(collection, values)
    }
}
