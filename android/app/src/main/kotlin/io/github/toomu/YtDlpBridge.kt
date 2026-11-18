package io.github.toomu

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.yausername.aria2c.Aria2c
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLException
import com.yausername.youtubedl_android.YoutubeDLRequest
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/**
 * Flutter bridge to youtubedl-android (yt-dlp + Python + QuickJS + FFmpeg).
 *
 * Methods (channel "toomu/ytdlp"):
 *  - init()                       -> yt-dlp version
 *  - update(channel)              -> "DONE" | "ALREADY_UP_TO_DATE"
 *  - version()                    -> yt-dlp version
 *  - needsUpdate()                -> true if running the bundled yt-dlp
 *  - run(id, args: List<String>)  -> {exitCode, out, err}; progress lines are
 *                                    streamed on "toomu/ytdlp/progress" as {id, line}
 *  - cancel(id)                   -> Boolean
 *
 * Every call replies exactly once, on the main thread.
 */
class YtDlpBridge(private val context: Context, messenger: BinaryMessenger) {

    private val io = Executors.newCachedThreadPool()
    private val main = Handler(Looper.getMainLooper())
    private var progressSink: EventChannel.EventSink? = null

    @Volatile private var initialized = false

    init {
        MethodChannel(messenger, "toomu/ytdlp").setMethodCallHandler { call, result ->
            when (call.method) {
                "init" -> async(result) { ensureInit(); currentVersion() }
                "version" -> async(result) { ensureInit(); currentVersion() }
                // No release tag recorded: the bundled yt-dlp (first launch,
                // or restored after a cut-short update), likely months old.
                "needsUpdate" -> async(result) { ensureInit(); prefs.getString("tag", null) == null }
                "update" -> async(result) {
                    ensureInit()
                    update(call.argument<String>("channel") == "nightly")
                }
                "run" -> {
                    val id = call.argument<String>("id")
                    val args = call.argument<List<String>>("args")
                    if (id == null || args == null) {
                        result.error("ARG", "id and args are required", null)
                    } else {
                        async(result) { run(id, args) }
                    }
                }
                "cancel" -> {
                    val id = call.argument<String>("id")
                    result.success(id != null && YoutubeDL.destroyProcessById(id))
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, "toomu/ytdlp/progress").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                progressSink = events
            }

            override fun onCancel(arguments: Any?) {
                progressSink = null
            }
        })
    }

    @Synchronized
    private fun ensureInit() {
        if (initialized) return
        repairBinary()
        val packages = UnpackedPackages(File(File(context.noBackupFilesDir, YoutubeDL.baseName), "packages"))
        val removed = packages.repair()
        if (removed.isNotEmpty()) Log.w("YtDlpBridge", "unpacking again (files were cut short): $removed")
        val before = packages.snapshot()
        // First launch unpacks Python/FFmpeg (a few seconds); later launches are instant.
        YoutubeDL.init(context)
        FFmpeg.init(context)
        try {
            Aria2c.init(context)
        } catch (_: Exception) {
            // Optional: downloads fall back to yt-dlp's own downloader.
        }
        // The library doesn't flush what it unzips; a restart right after
        // would cut those files short again.
        if (packages.snapshot() != before) flushToDisk()
        initialized = true
    }

    private fun flushToDisk() {
        try {
            Runtime.getRuntime().exec(arrayOf("sync")).waitFor()
        } catch (e: Exception) {
            Log.w("YtDlpBridge", "sync failed", e)
        }
    }

    /**
     * Runs yt-dlp with [args]. The last arg must be the URL (YoutubeDLRequest
     * appends URLs after options, so it is passed separately).
     */
    private fun run(id: String, args: List<String>): Map<String, Any?> {
        ensureInit()
        // Empty URL = no URL (e.g. with --load-info-json).
        val url = args.last()
        val request = if (url.isEmpty()) YoutubeDLRequest(emptyList<String>()) else YoutubeDLRequest(url)
        val commands = args.dropLast(1).flatMap { arg ->
            if (arg.startsWith("--toomu-aria2c=")) aria2cArgs(arg.substringAfter('=').toIntOrNull() ?: 4)
            else listOf(arg)
        }
        request.addCommands(commands)
        return try {
            // redirectErrorStream = false keeps stderr separate (error messages).
            val response = YoutubeDL.execute(request, id, false) { _, _, line ->
                // Skip huge lines (the info JSON): Dart only needs progress/status lines.
                if (line.length <= 2000) main.post { progressSink?.success(mapOf("id" to id, "line" to line)) }
            }
            mapOf("exitCode" to response.exitCode, "out" to response.out, "err" to response.err)
        } catch (e: YoutubeDL.CanceledException) {
            mapOf("exitCode" to -1, "out" to "", "err" to "", "canceled" to true)
        } catch (e: YoutubeDLException) {
            // The library throws when yt-dlp exits with an error; hand it back
            // as a normal failed result so Dart can retry (other client,
            // built-in downloader) and log the details.
            mapOf("exitCode" to 1, "out" to "", "err" to (e.message ?: "The downloader failed"))
        }
    }

    private fun async(result: MethodChannel.Result, block: () -> Any?) {
        io.execute {
            try {
                val value = block()
                main.post { result.success(value) }
            } catch (e: Throwable) {
                Log.e("YtDlpBridge", "call failed", e)
                // An ExceptionInInitializerError has no message: the reason is in its causes.
                val message = generateSequence(e) { it.cause }.take(5).joinToString(" <- ") { it.toString() }
                main.post { result.error("YTDLP", message, null) }
            }
        }
    }

    /**
     * aria2c with [connections] parallel connections per file. These args
     * replace the library's own aria2c args, so they repeat its two (CA
     * certificate path for TLS, progress lines every second).
     */
    private fun aria2cArgs(connections: Int): List<String> {
        val n = connections.coerceIn(2, 16)
        val caCert = File(context.noBackupFilesDir,
            "${YoutubeDL.baseName}/packages/python/usr/etc/tls/cert.pem").absolutePath
        return listOf(
            "--downloader", "libaria2c.so",
            "--downloader-args",
            "aria2c:-x $n -s $n -k 1M --file-allocation=none --summary-interval=1 " +
                // Same IP version as yt-dlp (-4): links are tied to it.
                "--disable-ipv6=true --console-log-level=warn --ca-certificate=$caCert",
        )
    }

    // ------------------------------------------------------------ updates
    //
    // The library's updater asks the GitHub *API* first, which allows only
    // 60 requests/hour per IP. Behind carrier-grade NAT that quota is shared
    // with many strangers and is often used up, so updates never happened.
    // This updater only uses github.com release pages/files (not rate-limited):
    // the latest tag comes from the /releases/latest redirect.

    private val prefs get() = context.getSharedPreferences("toomu_ytdlp", Context.MODE_PRIVATE)

    private fun repo(nightly: Boolean) = if (nightly) "yt-dlp/yt-dlp-nightly-builds" else "yt-dlp/yt-dlp"

    /** Installed yt-dlp version, asking yt-dlp itself if we never recorded one. */
    private fun currentVersion(): String? {
        prefs.getString("version", null)?.let { return it }
        val v = runVersion() ?: return null
        prefs.edit().putString("version", v).apply()
        return v
    }

    private fun runVersion(): String? = try {
        val request = YoutubeDLRequest(emptyList<String>()).addOption("--version")
        YoutubeDL.execute(request, null, false, null).out
            .lines().map { it.trim() }.lastOrNull { it.isNotEmpty() }
    } catch (e: Exception) {
        null
    }

    /** Latest release tag, e.g. "2026.10.26", from the redirect target. */
    private fun latestTag(nightly: Boolean): String {
        val conn = URL("https://github.com/${repo(nightly)}/releases/latest").openConnection() as HttpURLConnection
        try {
            conn.instanceFollowRedirects = false
            conn.requestMethod = "HEAD"
            conn.connectTimeout = 20_000
            conn.readTimeout = 20_000
            conn.setRequestProperty("User-Agent", "Toomu")
            val location = conn.getHeaderField("Location")
                ?: throw IOException("GitHub returned HTTP ${conn.responseCode} without a redirect")
            return location.substringAfterLast("/tag/").ifEmpty { throw IOException("No tag in $location") }
        } finally {
            conn.disconnect()
        }
    }

    @Synchronized
    private fun update(nightly: Boolean): String {
        val tag = latestTag(nightly)
        if (tag == prefs.getString("tag", null) && File(binaryDir(), YoutubeDL.ytdlpBin).exists()) {
            return "ALREADY_UP_TO_DATE"
        }

        // Download to cache first; never touch the working binary until verified.
        val tmp = File.createTempFile("yt-dlp", null, context.cacheDir)
        try {
            val conn = URL("https://github.com/${repo(nightly)}/releases/download/$tag/yt-dlp")
                .openConnection() as HttpURLConnection
            conn.connectTimeout = 30_000
            conn.readTimeout = 60_000
            conn.setRequestProperty("User-Agent", "Toomu")
            conn.instanceFollowRedirects = true
            if (conn.responseCode != 200) throw IOException("Download failed: HTTP ${conn.responseCode}")
            conn.inputStream.use { input -> tmp.outputStream().use { input.copyTo(it) } }
            conn.disconnect()
            if (!YtDlpBinaryFiles.isWhole(tmp)) throw IOException("Downloaded file too small (${tmp.length()} bytes)")

            binaryDir().mkdirs()
            val files = files()
            val target = files.binary
            val backup = files.backup
            if (target.exists()) files.durableCopy(target, backup)
            files.durableCopy(tmp, target)

            // Verify the new binary actually runs; otherwise roll back.
            val version = runVersion()
            if (version == null) {
                if (backup.exists()) files.durableCopy(backup, target)
                throw IOException("The new engine version $tag did not start; kept the previous one")
            }
            backup.delete()
            prefs.edit().putString("tag", tag).putString("version", version).apply()
            return "DONE"
        } finally {
            tmp.delete()
        }
    }

    /** See [YtDlpBinaryFiles.repair]. */
    private fun repairBinary() {
        if (!files().repair()) return
        Log.w("YtDlpBridge", "yt-dlp was cut short (interrupted update); restored")
        prefs.edit().remove("tag").remove("version").apply()
    }

    private fun files() = YtDlpBinaryFiles(binaryDir(), YoutubeDL.ytdlpBin)

    private fun binaryDir() = File(File(context.noBackupFilesDir, YoutubeDL.baseName), YoutubeDL.ytdlpDirName)

    fun dispose() = io.shutdown()
}
