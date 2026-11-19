package io.github.toomu

import android.app.PictureInPictureParams
import android.app.RecoverableSecurityException
import android.app.RemoteAction
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.drawable.Icon
import android.util.Rational
import android.content.ComponentName
import android.content.ContentUris
import android.content.Intent
import android.net.Uri
import android.os.SystemClock
import android.provider.Settings
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Size
import android.view.WindowManager
import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

// audio_service's activity keeps the Flutter engine alive for background playback; its Fragment variant
// because local_auth's fingerprint prompt (private folder) needs a FragmentActivity.
class MainActivity : AudioServiceFragmentActivity() {

    // audio_service keeps the Flutter engine (and queued downloads) running
    // after the activity is destroyed, so these live as long as the process.
    companion object {
        private val io = Executors.newFixedThreadPool(3)
        private var ytDlp: YtDlpBridge? = null
        private var ytDlpEngine: FlutterEngine? = null
    }

    private val main = Handler(Looper.getMainLooper())

    private var intents: MethodChannel? = null

    // ---------------------------------------------------- picture-in-picture

    private var videoChannel: MethodChannel? = null

    /** Enter PiP when the user leaves the app (set while a video plays). */
    private var pipAutoEnter = false
    private var pipAspect = Rational(16, 9)
    private var pipPlaying = true

    private fun pipSupported() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
        packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    private fun updatePipParams(call: io.flutter.plugin.common.MethodCall) {
        val w = call.argument<Int>("width") ?: 16
        val h = call.argument<Int>("height") ?: 9
        // Android only accepts ratios between 1:2.39 and 2.39:1.
        val ratio = (w.toFloat() / h.coerceAtLeast(1)).coerceIn(0.42f, 2.39f)
        pipAspect = Rational((ratio * 1000).toInt(), 1000)
        pipPlaying = call.argument<Boolean>("playing") ?: true
        pipAutoEnter = call.argument<Boolean>("autoEnter") ?: false
        if (pipSupported()) {
            try {
                setPictureInPictureParams(buildPipParams())
            } catch (_: Exception) {}
        }
    }

    private fun buildPipParams(): PictureInPictureParams {
        fun action(icon: Int, title: String, act: String, code: Int) = RemoteAction(
            Icon.createWithResource(this, icon), title, title, VideoMediaBridge.pending(this, act, code)
        )
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(pipAspect)
            .setActions(listOf(
                action(android.R.drawable.ic_media_rew, "Back 10 s", VideoMediaBridge.ACTION_REWIND, 21),
                if (pipPlaying) action(android.R.drawable.ic_media_pause, "Pause", VideoMediaBridge.ACTION_PLAY_PAUSE, 22)
                else action(android.R.drawable.ic_media_play, "Play", VideoMediaBridge.ACTION_PLAY_PAUSE, 22),
                action(android.R.drawable.ic_media_ff, "Forward 10 s", VideoMediaBridge.ACTION_FORWARD, 23),
            ))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(pipAutoEnter) // Android 12+: smooth enter on Home
            builder.setSeamlessResizeEnabled(true)
        }
        return builder.build()
    }

    private fun enterPip(): Boolean {
        if (!pipSupported()) return false
        return try {
            enterPictureInPictureMode(buildPipParams())
        } catch (_: Exception) {
            false
        }
    }

    /** Android 8–11: no auto-enter flag, so enter PiP when the user leaves. */
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (pipAutoEnter && Build.VERSION.SDK_INT in Build.VERSION_CODES.O until Build.VERSION_CODES.S) enterPip()
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        videoChannel?.invokeMethod("pipChanged", isInPictureInPictureMode)
    }

    /** A share/bubble intent waiting for Dart to ask for it (cold start). */
    private var pendingIntent: Map<String, Any?>? = null

    /** Turns a launching intent into {type, text} for Dart, or null. */
    private fun payloadOf(intent: Intent?): Map<String, Any?>? = when (intent?.action) {
        Intent.ACTION_SEND -> intent.getStringExtra(Intent.EXTRA_TEXT)?.let { mapOf("type" to "share", "text" to it) }
        Intent.ACTION_VIEW -> intent.dataString?.let { data ->
            // "Open with Toomu" from a file manager → play the video.
            if (intent.type?.startsWith("video/") == true || data.startsWith("content://") || data.startsWith("file://")) {
                mapOf("type" to "video", "uri" to data, "name" to displayNameOf(intent.data))
            } else {
                mapOf("type" to "share", "text" to data)
            }
        }
        DownloadProgressService.ACTION_OPEN_DOWNLOADS -> mapOf("type" to "openDownloads")
        BubbleService.ACTION_BUBBLE_TAP -> mapOf(
            "type" to "bubble",
            "title" to intent.getStringExtra("title"),
            "artist" to intent.getStringExtra("artist"),
            "durationMs" to intent.getLongExtra("durationMs", 0L),
            "mediaId" to intent.getStringExtra("mediaId"),
        )
        else -> null
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val payload = payloadOf(intent) ?: return
        val channel = intents
        if (channel != null) channel.invokeMethod("intent", payload) else pendingIntent = payload
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        if (ytDlpEngine !== flutterEngine) {
            ytDlp?.dispose()
            ytDlp = YtDlpBridge(applicationContext, messenger)
            ytDlpEngine = flutterEngine
        }

        // Links shared to Toomu ("Download with Toomu") and bubble taps.
        pendingIntent = payloadOf(intent)
        intents = MethodChannel(messenger, "toomu/intents").also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "initial" -> {
                        result.success(pendingIntent)
                        pendingIntent = null
                    }
                    else -> result.notImplemented()
                }
            }
        }

        MethodChannel(messenger, "toomu/clipboard").setMethodCallHandler { call, result ->
            val path = call.argument<String>("path")
            if (call.method != "copyImage" || path == null) return@setMethodCallHandler result.notImplemented()
            try {
                val shown = ImageClipboard.copy(
                    this,
                    java.io.File(path),
                    call.argument<String>("mimeType") ?: "image/*",
                    call.argument<String>("label") ?: "Image",
                )
                result.success(shown)
            } catch (e: Exception) {
                result.error("COPY", e.message, null)
            }
        }

        MethodChannel(messenger, "toomu/update").setMethodCallHandler { call, result ->
            val path = call.argument<String>("path")
            if (call.method != "install" || path == null) return@setMethodCallHandler result.notImplemented()
            io.execute {
                try {
                    UpdateReceiver.install(applicationContext, path)
                    main.post { result.success(null) }
                } catch (e: Exception) {
                    main.post { result.error("UPDATE", e.toString(), null) }
                }
            }
        }

        // Download progress notification (+ keeps downloads alive in background).
        MethodChannel(messenger, "toomu/download_notify").also { ch ->
            DownloadProgressService.listener = { action -> ch.invokeMethod("action", action) }
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "update" -> {
                        @Suppress("UNCHECKED_CAST")
                        val items = (call.argument<List<Map<String, Any?>>>("items") ?: emptyList()).map {
                            DownloadProgressService.Item(
                                id = it["id"] as? String ?: "",
                                title = it["title"] as? String ?: "",
                                thumb = it["thumb"] as? String,
                                progress = (it["progress"] as? Number)?.toInt() ?: -1,
                                status = it["status"] as? String ?: "",
                                kind = it["kind"] as? String ?: "",
                            )
                        }
                        DownloadProgressService.snapshot = DownloadProgressService.Snapshot(
                            title = call.argument<String>("title") ?: "Downloading",
                            text = call.argument<String>("text") ?: "",
                            progress = call.argument<Int>("progress") ?: -1,
                            items = items,
                        )
                        if (DownloadProgressService.running) {
                            DownloadProgressService.render(this)
                        } else {
                            val i = Intent(this, DownloadProgressService::class.java)
                            try {
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(i) else startService(i)
                            } catch (_: Exception) {
                                // Not allowed from the background right now; next tick retries.
                            }
                        }
                        result.success(null)
                    }
                    "stop" -> {
                        DownloadProgressService.snapshot = null
                        DownloadProgressService.clearCards(this)
                        // A service that hasn't reached startForeground yet must not be
                        // stopped (Android crashes the app); it stops itself instead.
                        if (DownloadProgressService.running) {
                            stopService(Intent(this, DownloadProgressService::class.java))
                        }
                        result.success(null)
                    }
                    "finished" -> {
                        DownloadProgressService.postFinished(
                            this,
                            call.argument<String>("id") ?: "0",
                            call.argument<String>("title") ?: "",
                            call.argument<String>("thumb"),
                            call.argument<String>("kind"),
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        // Video player: picture-in-picture + background play.
        videoChannel = MethodChannel(messenger, "toomu/video").also { ch ->
            VideoMediaBridge.listener = { action -> ch.invokeMethod("action", action) }
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "pipSupported" -> result.success(pipSupported())
                    "clock" -> result.success(
                        mapOf(
                            "elapsed" to SystemClock.elapsedRealtime(),
                            "boot" to runCatching { Settings.Global.getInt(contentResolver, Settings.Global.BOOT_COUNT) }.getOrNull(),
                        ),
                    )
                    "secure" -> {
                        // Keeps the private folder out of the Recents thumbnail and screenshots.
                        if (call.argument<Boolean>("on") == true) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        result.success(null)
                    }
                    "enterPip" -> {
                        updatePipParams(call)
                        result.success(enterPip())
                    }
                    "updatePip" -> {
                        updatePipParams(call)
                        result.success(null)
                    }
                    "startBackground", "updateBackground" -> {
                        val old = VideoBackgroundService.state
                        VideoBackgroundService.state = VideoBackgroundService.State(
                            title = call.argument<String>("title") ?: old.title,
                            subtitle = call.argument<String>("subtitle") ?: old.subtitle,
                            playing = call.argument<Boolean>("playing") ?: old.playing,
                            positionMs = call.argument<Number>("position")?.toLong() ?: old.positionMs,
                            durationMs = call.argument<Number>("duration")?.toLong() ?: old.durationMs,
                            speed = call.argument<Number>("speed")?.toFloat() ?: old.speed,
                            hasNext = call.argument<Boolean>("hasNext") ?: old.hasNext,
                            // "art" is only sent when the video changes (null = none).
                            art = if (call.hasArgument("art")) decodeArt(call.argument<ByteArray>("art")) else old.art,
                        )
                        if (VideoBackgroundService.running) {
                            VideoBackgroundService.refresh()
                            result.success(true)
                        } else {
                            val i = Intent(this, VideoBackgroundService::class.java)
                            try {
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(i) else startService(i)
                                result.success(true)
                            } catch (e: Exception) {
                                result.success(false) // e.g. not allowed from background
                            }
                        }
                    }
                    "stopBackground" -> {
                        stopService(Intent(this, VideoBackgroundService::class.java))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        // Floating download bubble over YouTube.
        MethodChannel(messenger, "toomu/bubble").setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(mapOf(
                    "overlay" to BubbleService.canDrawOverlays(this),
                    "usage" to BubbleService.hasUsageAccess(this),
                    "running" to BubbleHost.showing,
                    "notifications" to MediaNotificationListener.hasAccess(this),
                ))
                "openNotificationSettings" -> {
                    val component = ComponentName(this, MediaNotificationListener::class.java)
                    val direct = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS)
                            .putExtra(Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME, component.flattenToString())
                    } else null
                    try {
                        startActivity(direct ?: Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                    } catch (e: Exception) {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                    }
                    result.success(null)
                }
                "openOverlaySettings" -> {
                    startActivity(Intent(
                        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                        Uri.parse("package:$packageName"),
                    ))
                    result.success(null)
                }
                "openUsageSettings" -> {
                    startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                    result.success(null)
                }
                "start" -> {
                    BubbleHost.setWanted(this, true)
                    result.success(null)
                }
                "stop" -> {
                    BubbleHost.setWanted(this, false)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, "toomu/diagnostics").setMethodCallHandler { call, result ->
            when (call.method) {
                // Why earlier runs ended (Android 11+): native crashes and the system's kills never reach the
                // app's own log.
                "exitsSince" -> {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
                        result.success(emptyList<Map<String, Any?>>())
                    } else {
                        val since = call.argument<Number>("since")?.toLong() ?: 0L
                        val am = getSystemService(ACTIVITY_SERVICE) as android.app.ActivityManager
                        result.success(
                            am.getHistoricalProcessExitReasons(packageName, 0, 5)
                                .filter { it.timestamp > since }
                                .map {
                                    mapOf(
                                        "time" to it.timestamp,
                                        "reason" to it.reason,
                                        "status" to it.status,
                                        "description" to it.description,
                                        "importance" to it.importance,
                                        "rssKb" to it.rss,
                                        "process" to it.processName,
                                    )
                                },
                        )
                    }
                }
                "thermal" -> {
                    val pm = getSystemService(POWER_SERVICE) as android.os.PowerManager
                    result.success(if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) pm.currentThermalStatus else -1)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, "toomu/media_scanner").setMethodCallHandler { call, result ->
            when (call.method) {
                "scanFile" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("ARG", "path is required", null)
                    } else {
                        MediaScannerConnection.scanFile(applicationContext, arrayOf(path), null, null)
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Device music library. Every branch replies exactly once, always on
        // the main thread, so it cannot hit "Reply already submitted" crashes.
        MethodChannel(messenger, "toomu/media_library").setMethodCallHandler { call, result ->
            when (call.method) {
                "songs" -> runAsync(result) { querySongs() }
                "delete" -> {
                    val ids = call.argument<List<Number>>("ids")?.map { it.toLong() }
                    if (ids.isNullOrEmpty()) result.error("ARG", "ids are required", null)
                    else deleteMedia(
                        ids,
                        if (call.argument<String>("kind") == "video") MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                        else MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                        result,
                    )
                }
                "videos" -> runAsync(result) { queryVideos() }
                "videoThumb" -> {
                    val id = (call.argument<Number>("id"))?.toLong()
                    val size = call.argument<Int>("size") ?: 320
                    if (id == null) result.error("ARG", "id is required", null)
                    else runAsync(result) { loadVideoThumb(id, size) }
                }
                "artwork" -> {
                    val id = (call.argument<Number>("id"))?.toLong()
                    val size = call.argument<Int>("size") ?: 200
                    if (id == null) result.error("ARG", "id is required", null)
                    else runAsync(result) { loadArtwork(id, size) }
                }
                else -> result.notImplemented()
            }
        }
    }

    // ------------------------------------------------------------- delete

    private val deleteRequestCode = 4711
    private var pendingDelete: MethodChannel.Result? = null
    private val deleteQueue = ArrayDeque<Uri>()
    private var askedUri: Uri? = null
    private val deleteBlocked = mutableListOf<Uri>() // kept across Android 10's one-file-at-a-time dialogs

    private fun deleteMedia(ids: List<Long>, collection: Uri, result: MethodChannel.Result) {
        if (pendingDelete != null) {
            result.error("BUSY", "Another delete is waiting for confirmation", null)
            return
        }
        pendingDelete = result
        deleteQueue.clear()
        deleteBlocked.clear()
        ids.mapTo(deleteQueue) { ContentUris.withAppendedId(collection, it) }
        continueDelete()
    }

    private fun continueDelete() {
        val result = pendingDelete ?: return
        // Toomu's own files go directly; other apps' files need the user's OK in a system dialog (Android 10+).
        while (deleteQueue.isNotEmpty()) {
            val uri = deleteQueue.removeFirst()
            try {
                contentResolver.delete(uri, null, null)
            } catch (e: SecurityException) {
                if (Build.VERSION.SDK_INT == Build.VERSION_CODES.Q && e is RecoverableSecurityException) {
                    // Android 10 asks one file at a time: the rest carry on in onActivityResult.
                    askedUri = uri
                    @Suppress("DEPRECATION")
                    startIntentSenderForResult(e.userAction.actionIntent.intentSender, deleteRequestCode, null, 0, 0, 0)
                    return
                }
                deleteBlocked += uri
            }
        }
        if (deleteBlocked.isEmpty()) {
            pendingDelete = null
            result.success(true)
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // Android 11+: one system dialog for all of them; it deletes on "Allow".
            val request = MediaStore.createDeleteRequest(contentResolver, deleteBlocked.toList())
            @Suppress("DEPRECATION")
            startIntentSenderForResult(request.intentSender, deleteRequestCode, null, 0, 0, 0)
        } else {
            pendingDelete = null
            deleteBlocked.clear()
            result.error("PERMISSION", "Not allowed to delete this file", null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != deleteRequestCode) return
        val result = pendingDelete ?: return
        val asked = askedUri
        askedUri = null
        if (resultCode != RESULT_OK) {
            pendingDelete = null
            deleteQueue.clear()
            deleteBlocked.clear()
            result.success(false)
        } else if (asked != null) {
            runCatching { contentResolver.delete(asked, null, null) }
            continueDelete()
        } else {
            pendingDelete = null
            deleteBlocked.clear()
            result.success(true)
        }
    }

    private fun runAsync(result: MethodChannel.Result, block: () -> Any?) {
        io.execute {
            try {
                val value = block()
                main.post { result.success(value) }
            } catch (e: SecurityException) {
                main.post { result.error("PERMISSION", e.message, null) }
            } catch (e: Exception) {
                main.post { result.error("ERROR", e.message, null) }
            }
        }
    }

    /** Device videos (MediaStore), newest first. */
    private fun queryVideos(): List<Map<String, Any?>> {
        val uri = MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        val projection = arrayOf(
            MediaStore.Video.Media._ID,
            MediaStore.Video.Media.DISPLAY_NAME,
            MediaStore.Video.Media.TITLE,
            MediaStore.Video.Media.DURATION,
            MediaStore.Video.Media.DATA,
            MediaStore.Video.Media.SIZE,
            MediaStore.Video.Media.WIDTH,
            MediaStore.Video.Media.HEIGHT,
            MediaStore.Video.Media.DATE_ADDED,
            MediaStore.Video.Media.BUCKET_DISPLAY_NAME,
        ).let { base ->
            // Phone-camera videos are often stored 1920×1080 with "rotate
            // 90°": the real shape needs the orientation too (Android 10+).
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) base + MediaStore.Video.Media.ORIENTATION else base
        }
        val videos = ArrayList<Map<String, Any?>>()
        contentResolver.query(uri, projection, null, null, "${MediaStore.Video.Media.DATE_ADDED} DESC")?.use { c ->
            fun col(name: String) = c.getColumnIndexOrThrow(name)
            val id = col(MediaStore.Video.Media._ID)
            val name = col(MediaStore.Video.Media.DISPLAY_NAME)
            val title = col(MediaStore.Video.Media.TITLE)
            val duration = col(MediaStore.Video.Media.DURATION)
            val data = col(MediaStore.Video.Media.DATA)
            val size = col(MediaStore.Video.Media.SIZE)
            val width = col(MediaStore.Video.Media.WIDTH)
            val height = col(MediaStore.Video.Media.HEIGHT)
            val added = col(MediaStore.Video.Media.DATE_ADDED)
            val bucket = col(MediaStore.Video.Media.BUCKET_DISPLAY_NAME)
            val orientation = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                c.getColumnIndex(MediaStore.Video.Media.ORIENTATION)
            } else {
                -1
            }
            while (c.moveToNext()) {
                val videoId = c.getLong(id)
                // Shown sideways (rotated 90°/270°): width and height swap.
                val turned = orientation >= 0 && (c.getInt(orientation) == 90 || c.getInt(orientation) == 270)
                videos.add(
                    mapOf(
                        "id" to videoId,
                        "name" to c.getString(name),
                        "title" to c.getString(title),
                        "duration" to c.getLong(duration),
                        "path" to c.getString(data),
                        "size" to c.getLong(size),
                        "width" to c.getInt(if (turned) height else width),
                        "height" to c.getInt(if (turned) width else height),
                        "dateAdded" to c.getLong(added),
                        "folder" to c.getString(bucket),
                        "uri" to ContentUris.withAppendedId(uri, videoId).toString(),
                    )
                )
            }
        }
        return videos
    }

    /** JPEG frame of a video for its list thumbnail. */
    private fun loadVideoThumb(id: Long, size: Int): ByteArray? {
        val uri = ContentUris.withAppendedId(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, id)
        val bitmap: Bitmap? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                contentResolver.loadThumbnail(uri, Size(size, size * 9 / 16), null)
            } catch (_: Exception) {
                null
            }
        } else {
            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(applicationContext, uri)
                retriever.getFrameAtTime(2_000_000)
            } catch (_: Exception) {
                null
            } finally {
                try { retriever.release() } catch (_: Exception) {}
            }
        }
        bitmap ?: return null
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, 80, out)
        return out.toByteArray()
    }

    /** File name of a content:// URI opened from another app. */
    private fun displayNameOf(uri: Uri?): String? {
        uri ?: return null
        if (uri.scheme == "file") return uri.lastPathSegment
        return try {
            contentResolver.query(uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
        } catch (_: Exception) {
            null
        }
    }

    private fun querySongs(): List<Map<String, Any?>> {
        val uri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.ALBUM_ID,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.DATA,
            MediaStore.Audio.Media.DATE_ADDED,
            MediaStore.Audio.Media.SIZE,
        )
        val selection = "${MediaStore.Audio.Media.IS_MUSIC} != 0 AND ${MediaStore.Audio.Media.DURATION} > 10000"
        val songs = ArrayList<Map<String, Any?>>()
        contentResolver.query(uri, projection, selection, null, "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE ASC")
            ?.use { c ->
                val id = c.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
                val title = c.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
                val artist = c.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
                val album = c.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
                val albumId = c.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM_ID)
                val duration = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
                val data = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
                val added = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_ADDED)
                val size = c.getColumnIndexOrThrow(MediaStore.Audio.Media.SIZE)
                while (c.moveToNext()) {
                    val songId = c.getLong(id)
                    songs.add(
                        mapOf(
                            "id" to songId,
                            "title" to (c.getString(title) ?: "Unknown"),
                            "artist" to c.getString(artist),
                            "album" to c.getString(album),
                            "albumId" to c.getLong(albumId),
                            "duration" to c.getLong(duration),
                            "path" to c.getString(data),
                            "dateAdded" to c.getLong(added),
                            "size" to c.getLong(size),
                            "uri" to ContentUris.withAppendedId(uri, songId).toString(),
                        )
                    )
                }
            }
        return songs
    }

    /** JPEG bytes of the song's cover, or null if it has none. */
    private fun loadArtwork(id: Long, size: Int): ByteArray? {
        val uri = ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id)
        val bitmap: Bitmap? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                contentResolver.loadThumbnail(uri, Size(size, size), null)
            } catch (_: Exception) {
                null
            }
        } else {
            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(applicationContext, uri)
                retriever.embeddedPicture?.let { bytes ->
                    val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts)
                    var sample = 1
                    while (opts.outWidth / (sample * 2) >= size) sample *= 2
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size,
                        BitmapFactory.Options().apply { inSampleSize = sample })
                }
            } catch (_: Exception) {
                null
            } finally {
                try { retriever.release() } catch (_: Exception) {}
            }
        }
        bitmap ?: return null
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, 85, out)
        return out.toByteArray()
    }

    override fun onDestroy() {
        VideoMediaBridge.listener = null
        stopService(Intent(this, VideoBackgroundService::class.java))
        super.onDestroy()
    }
}
