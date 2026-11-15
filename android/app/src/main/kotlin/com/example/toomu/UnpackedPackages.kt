package com.example.toomu

import java.io.File

/**
 * The library's unpacked packages ([root]/python, ffmpeg, aria2c), kept free
 * of Android so it can be unit-tested on the JVM.
 *
 * The library unzips them without flushing to disk. A restart soon after
 * leaves files with their names but no data: 0-byte `libgmp.so`,
 * `libavutil.so`… Then aria2c can't link, ffmpeg can't run, yt-dlp can't
 * merge, and every download fails at the merge step and starts over. The
 * library only unzips again when a package's folder is missing, so a broken
 * package is deleted before it starts.
 */
class UnpackedPackages(private val root: File) {

    private fun packages(): List<File> = root.listFiles()?.filter { it.isDirectory }.orEmpty()

    /** Packages with at least one empty library or program. */
    fun broken(): List<File> = packages().filter { pkg -> pkg.walkTopDown().any(::isEmptyBinary) }

    /** Deletes [broken] packages; returns their names. */
    fun repair(): List<String> = broken().map { it.deleteRecursively(); it.name }

    /** Each package folder's change time; compare two to see what was unzipped. */
    fun snapshot(): Map<String, Long> = packages().associate { it.name to it.lastModified() }

    companion object {
        private val sharedLibrary = Regex("""^lib.+\.so(\.\d+)*$""")

        /**
         * A shared library or program with no bytes. Other empty files are
         * normal (Python's empty `__init__.py`, empty `.pyc` caches that
         * Python rebuilds from source).
         */
        fun isEmptyBinary(file: File): Boolean =
            file.isFile && file.length() == 0L &&
                (sharedLibrary.matches(file.name) || file.parentFile?.name == "bin")
    }
}
