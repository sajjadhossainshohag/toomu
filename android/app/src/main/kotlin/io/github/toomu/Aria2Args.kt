package io.github.toomu

/**
 * yt-dlp's args for aria2c with [connections] parallel connections per file. They replace the library's own
 * aria2c args, so they repeat its two (CA certificate path for TLS, progress lines every second).
 *
 * aria2c writes each part of a file at its own offset, so a paused file is already about as long as the
 * start of its last part; the app reads the bytes it really has from aria2c's control file, saved every
 * second here (the default, 60 s, left a pause in the first minute showing the file's length).
 */
object Aria2Args {
    fun of(connections: Int, caCert: String): List<String> {
        val n = connections.coerceIn(2, 16)
        return listOf(
            "--downloader", "libaria2c.so",
            "--downloader-args",
            "aria2c:-x $n -s $n -k 1M --file-allocation=none --summary-interval=1 --auto-save-interval=1 " +
                // Same IP version as yt-dlp (-4): links are tied to it.
                "--disable-ipv6=true --console-log-level=warn --ca-certificate=$caCert",
        )
    }
}
