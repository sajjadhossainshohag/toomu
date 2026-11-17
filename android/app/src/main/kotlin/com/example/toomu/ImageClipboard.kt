package com.example.toomu

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import androidx.core.content.FileProvider
import java.io.File

/**
 * "Copy image" in the browser: puts a picture (saved under cache/clipboard)
 * on the clipboard as a content:// link, which apps that paste images read.
 * The clipboard grants the pasting app read access to the link.
 */
object ImageClipboard {
    fun authority(context: Context) = "${context.packageName}.images"

    /** Returns true when Android shows its own "copied" preview (13+). */
    fun copy(context: Context, file: File, mimeType: String, label: String): Boolean {
        val uri = FileProvider.getUriForFile(context, authority(context), file)
        val clip = ClipData(label, arrayOf(mimeType), ClipData.Item(uri))
        (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(clip)
        return Build.VERSION.SDK_INT >= 33
    }
}
