package com.example.toomu

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/**
 * Download progress in the notification bar. Also keeps downloads alive
 * while Toomu is in the background: yt-dlp/aria2c run as child processes,
 * which Android may freeze or kill without a foreground service.
 *
 * Layout:
 *  - one download  → a single card: thumbnail, title, "45% · 3.2 MB/s ·
 *    12 s left", progress bar, Pause / Cancel.
 *  - several       → a summary ("Downloading 3 files") with one card per
 *    download grouped under it, each with its own buttons.
 *
 * Dart sends a [Snapshot] about once a second; the first starts the
 * service, later ones update the same notifications.
 */
class DownloadProgressService : Service() {

    /** One running download as shown in its card. */
    data class Item(
        val id: String,
        val title: String,
        val thumb: String?,
        /** 0..1000, or -1 while merging / converting / starting. */
        val progress: Int,
        val status: String,
        val kind: String,
    )

    data class Snapshot(
        val title: String,
        val text: String,
        val progress: Int,
        val items: List<Item>,
    )

    companion object {
        const val ACTION_OPEN_DOWNLOADS = "com.example.toomu.OPEN_DOWNLOADS"
        const val ACTION_PAUSE_ALL = "com.example.toomu.downloads.PAUSE_ALL"
        const val ACTION_PAUSE = "com.example.toomu.downloads.PAUSE"
        const val ACTION_CANCEL = "com.example.toomu.downloads.CANCEL"
        const val EXTRA_ID = "id"

        private const val CHANNEL_PROGRESS = "toomu_downloads"
        private const val CHANNEL_DONE = "toomu_downloads_done"
        private const val GROUP_ACTIVE = "toomu.downloads.active"
        private const val GROUP_DONE = "toomu.downloads.done"
        const val NOTIFICATION_ID = 7303

        /** Brand violet: tints the icon, app name, buttons and progress bar. */
        private const val ACCENT = 0xFF7C4DFF.toInt()

        @Volatile var running = false
            private set

        /** Latest state from Dart; the service renders from it. */
        @Volatile var snapshot: Snapshot? = null

        /** Set by MainActivity: forwards notification buttons to Dart. */
        @Volatile var listener: ((String) -> Unit)? = null
        private val main = Handler(Looper.getMainLooper())

        /** Card notifications currently posted (multi-download mode). */
        private val posted = mutableSetOf<Int>()

        fun dispatch(action: String, id: String?) {
            val message = when (action) {
                ACTION_PAUSE_ALL -> "pauseAll"
                ACTION_PAUSE -> "pause:$id"
                ACTION_CANCEL -> "cancel:$id"
                else -> return
            }
            main.post { listener?.invoke(message) }
        }

        // ------------------------------------------------------- thumbnails

        private val thumbs = ConcurrentHashMap<String, Bitmap>()
        private val loading = ConcurrentHashMap.newKeySet<String>()
        private val io = Executors.newSingleThreadExecutor()

        /** Cached thumbnail, or null (and starts fetching it). */
        private fun thumb(context: Context, url: String?): Bitmap? {
            if (url.isNullOrBlank()) return null
            thumbs[url]?.let { return it }
            if (loading.add(url)) {
                val app = context.applicationContext
                io.execute {
                    try {
                        val conn = URL(url).openConnection() as HttpURLConnection
                        conn.connectTimeout = 8000
                        conn.readTimeout = 8000
                        val raw = conn.inputStream.use { BitmapFactory.decodeStream(it) }
                        conn.disconnect()
                        if (raw != null) {
                            thumbs[url] = squareCrop(raw, 256)
                            if (thumbs.size > 40) thumbs.keys.firstOrNull()?.let { thumbs.remove(it) }
                            // Show it right away rather than on the next tick.
                            main.post { if (running) render(app) }
                        }
                    } catch (_: Exception) {
                        // No thumbnail; the card still works without it.
                    } finally {
                        loading.remove(url)
                    }
                }
            }
            return null
        }

        /** Center square (YouTube thumbnails are letterboxed 4:3). */
        private fun squareCrop(src: Bitmap, size: Int): Bitmap {
            val side = minOf(src.width, src.height)
            val crop = Bitmap.createBitmap(src, (src.width - side) / 2, (src.height - side) / 2, side, side)
            return Bitmap.createScaledBitmap(crop, size, size, true)
        }

        // ---------------------------------------------------------- helpers

        private fun channels(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_PROGRESS, "Download progress", NotificationManager.IMPORTANCE_LOW)
                    .apply { setShowBadge(false) }
            )
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_DONE, "Finished downloads", NotificationManager.IMPORTANCE_DEFAULT)
            )
        }

        private fun builder(context: Context, channel: String): Notification.Builder {
            val b = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(context, channel)
            else @Suppress("DEPRECATION") Notification.Builder(context)
            return b.setSmallIcon(R.drawable.ic_stat_toomu).setColor(ACCENT)
        }

        private fun openDownloads(context: Context, code: Int): PendingIntent = PendingIntent.getActivity(
            context, code,
            Intent(context, MainActivity::class.java)
                .setAction(ACTION_OPEN_DOWNLOADS)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        private fun button(context: Context, label: String, action: String, id: String?, icon: Int): Notification.Action {
            val intent = Intent(context, DownloadActionReceiver::class.java).setAction(action)
            if (id != null) intent.putExtra(EXTRA_ID, id)
            val code = (action + (id ?: "")).hashCode()
            return Notification.Action.Builder(
                Icon.createWithResource(context, icon),
                label,
                PendingIntent.getBroadcast(
                    context, code, intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                ),
            ).build()
        }

        private fun cardId(id: String) = 0x5000000 or (id.hashCode() and 0xFFFFFF)

        /** Progress bar: Android 16's progress style (brand-coloured,
         *  rounded), the classic bar elsewhere (tinted by the accent). */
        private fun Notification.Builder.withProgress(context: Context, progress: Int): Notification.Builder {
            val indeterminate = progress < 0
            val value = progress.coerceIn(0, 1000)
            if (Build.VERSION.SDK_INT >= 36) {
                setStyle(
                    Notification.ProgressStyle()
                        .setStyledByProgress(false)
                        .setProgressSegments(listOf(Notification.ProgressStyle.Segment(1000).setColor(ACCENT)))
                        .setProgressTrackerIcon(Icon.createWithResource(context, R.drawable.ic_stat_toomu).setTint(ACCENT))
                        .setProgress(value)
                        .setProgressIndeterminate(indeterminate)
                )
            } else {
                setProgress(1000, value, indeterminate)
            }
            return this
        }

        /** One download's card; [grouped] when it sits under the summary. */
        private fun card(context: Context, item: Item, grouped: Boolean): Notification {
            val b = builder(context, CHANNEL_PROGRESS)
                .setContentTitle(item.title)
                .setContentText(item.status)
                .setSubText(item.kind)
                .setContentIntent(openDownloads(context, 30))
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setShowWhen(false)
                .setCategory(Notification.CATEGORY_PROGRESS)
                .withProgress(context, item.progress)
                .addAction(button(context, "Pause", ACTION_PAUSE, item.id, android.R.drawable.ic_media_pause))
                .addAction(button(context, "Cancel", ACTION_CANCEL, item.id, android.R.drawable.ic_menu_close_clear_cancel))
            thumb(context, item.thumb)?.let { b.setLargeIcon(it) }
            if (grouped) b.setGroup(GROUP_ACTIVE)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                b.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
            }
            return b.build()
        }

        /** Header for several downloads; the cards sit under it. */
        private fun summary(context: Context, s: Snapshot): Notification {
            val inbox = Notification.InboxStyle().setBigContentTitle(s.title).setSummaryText(s.text)
            s.items.take(6).forEach { inbox.addLine("${it.title}  ·  ${it.status}") }
            val b = builder(context, CHANNEL_PROGRESS)
                .setContentTitle(s.title)
                .setContentText(s.text)
                .setContentIntent(openDownloads(context, 30))
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setShowWhen(false)
                .setCategory(Notification.CATEGORY_PROGRESS)
                .setProgress(1000, s.progress.coerceIn(0, 1000), s.progress < 0)
                .setStyle(inbox)
                .setGroup(GROUP_ACTIVE)
                .setGroupSummary(true)
                .addAction(button(context, "Pause all", ACTION_PAUSE_ALL, null, android.R.drawable.ic_media_pause))
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                b.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
            }
            return b.build()
        }

        /** The service's own notification for the current snapshot. */
        fun buildForeground(context: Context): Notification {
            channels(context)
            val s = snapshot ?: Snapshot("Downloading", "Starting…", -1, emptyList())
            return if (s.items.size == 1) card(context, s.items[0], grouped = false) else summary(context, s)
        }

        /** Redraws everything from [snapshot] (service already running). */
        fun render(context: Context) {
            val manager = context.getSystemService(NotificationManager::class.java)
            val s = snapshot ?: return
            manager.notify(NOTIFICATION_ID, buildForeground(context))
            val wanted = if (s.items.size > 1) s.items.associateBy { cardId(it.id) } else emptyMap()
            synchronized(posted) {
                (posted - wanted.keys).forEach { manager.cancel(it) }
                posted.retainAll(wanted.keys)
                wanted.forEach { (nid, item) ->
                    manager.notify(nid, card(context, item, grouped = true))
                    posted.add(nid)
                }
            }
        }

        fun clearCards(context: Context) {
            val manager = context.getSystemService(NotificationManager::class.java)
            synchronized(posted) {
                posted.forEach { manager.cancel(it) }
                posted.clear()
            }
        }

        /** "Download complete" — one per file (failures aren't notified). */
        fun postFinished(context: Context, id: String, title: String, thumbUrl: String?, kind: String?) {
            channels(context)
            val b = builder(context, CHANNEL_DONE)
                .setContentTitle("Download complete")
                .setContentText(title)
                .setSubText(kind)
                .setContentIntent(openDownloads(context, id.hashCode()))
                .setAutoCancel(true)
                .setGroup(GROUP_DONE)
            thumbs[thumbUrl ?: ""]?.let { b.setLargeIcon(it) }
            context.getSystemService(NotificationManager::class.java).notify(id.hashCode(), b.build())
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val n = buildForeground(this)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            } else {
                startForeground(NOTIFICATION_ID, n)
            }
            running = true
            render(this)
        } catch (e: Exception) {
            // Not allowed right now (e.g. started from the background).
            stopSelf()
        }
        return START_NOT_STICKY
    }

    // Android 15+: dataSync services get 6 h per day; not stopping here crashes the app.
    override fun onTimeout(startId: Int, fgsType: Int) {
        stopSelf()
    }

    override fun onDestroy() {
        running = false
        clearCards(this)
        super.onDestroy()
    }
}

class DownloadActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        DownloadProgressService.dispatch(action, intent.getStringExtra(DownloadProgressService.EXTRA_ID))
    }
}
