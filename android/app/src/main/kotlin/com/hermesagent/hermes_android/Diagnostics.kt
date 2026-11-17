package com.hermesagent.hermes_android

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File

/** mirrors engine state + log into public Downloads so it can be inspected
 * without root, adb, or a working method channel. */
object Diagnostics {
    private const val NAME = "hermes-engine-debug.txt"

    fun write(context: Context, text: String) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val resolver = context.contentResolver
                val uri = MediaStore.Downloads.EXTERNAL_CONTENT_URI
                val selection = "${MediaStore.Downloads.DISPLAY_NAME}=?"
                resolver.query(uri, arrayOf(MediaStore.Downloads._ID), selection, arrayOf(NAME), null)
                    ?.use { cursor ->
                        while (cursor.moveToNext()) {
                            resolver.delete(
                                uri,
                                "${MediaStore.Downloads._ID}=?",
                                arrayOf(cursor.getLong(0).toString()),
                            )
                        }
                    }
                val values = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, NAME)
                    put(MediaStore.Downloads.MIME_TYPE, "text/plain")
                    put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/hermes")
                }
                val target = resolver.insert(uri, values) ?: return
                resolver.openOutputStream(target)?.use { it.write(text.toByteArray(Charsets.UTF_8)) }
            } else {
                @Suppress("DEPRECATION")
                val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                File(dir, NAME).writeText(text)
            }
        } catch (_: Exception) {
            // Diagnostics must never affect the engine.
        }
    }
}
