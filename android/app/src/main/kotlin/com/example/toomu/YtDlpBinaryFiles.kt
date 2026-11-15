package com.example.toomu

import java.io.File
import java.io.FileOutputStream
import java.io.IOException

/**
 * The yt-dlp file on disk ([dir]/[name], plus its update backup), kept
 * free of Android so it can be unit-tested on the JVM.
 *
 * Python runs an empty or cut-short yt-dlp as a no-op that exits 0, so every
 * download "succeeds" without writing anything ("yt-dlp finished but the
 * file is missing"). That's what an update copy leaves behind when the phone
 * restarts before the data reaches the disk.
 */
class YtDlpBinaryFiles(private val dir: File, private val name: String) {

    val binary get() = File(dir, name)
    val backup get() = File(dir, "$name.bak")

    /**
     * Copies [from] over [to] so a crash or power loss leaves either the old
     * file or the whole new one: written beside it, flushed to disk, then
     * renamed into place.
     */
    fun durableCopy(from: File, to: File) {
        val part = File(to.parentFile, "${to.name}.part")
        try {
            from.inputStream().use { input ->
                FileOutputStream(part).use { out ->
                    input.copyTo(out)
                    out.fd.sync()
                }
            }
            if (!part.renameTo(to)) throw IOException("Couldn't replace ${to.name}")
        } finally {
            part.delete()
        }
    }

    /**
     * Before the library starts: a yt-dlp cut short by an interrupted update
     * is restored from its backup, or deleted so the library unpacks its
     * bundled copy again. Leftover partial copies are removed.
     *
     * @return true if the binary was broken (the caller forgets the saved
     *   tag so the next update check fetches the latest again).
     */
    fun repair(): Boolean {
        File(dir, "$name.part").delete()
        File(dir, "${backup.name}.part").delete()
        val target = binary
        if (!target.exists() || isWhole(target)) return false
        if (isWhole(backup)) durableCopy(backup, target) else target.delete()
        backup.delete()
        return true
    }

    companion object {
        /** yt-dlp's zipapp is ~3 MB; anything under 1 MB is broken. */
        const val MIN_BYTES = 1_000_000L

        fun isWhole(file: File) = file.length() >= MIN_BYTES
    }
}
