package io.github.toomu

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.drawable.Icon
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.IBinder
import android.os.SystemClock

/**
 * Video audio in the background (screen off / app left) through a standard
 * Android media session — the same system media controls music uses:
 * artwork, title, seek bar, play/pause, previous/next, lock screen and
 * headset buttons. Android freezes background apps that play without a
 * foreground service, so this runs while a video plays with background
 * play on. Started while the app is visible (Android 12+ requirement).
 */
class VideoBackgroundService : Service() {

    /** What the media controls show; sent from Dart. */
    data class State(
        val title: String = "Video",
        val subtitle: String = "",
        val playing: Boolean = true,
        val positionMs: Long = 0,
        val durationMs: Long = 0,
        val speed: Float = 1f,
        val hasNext: Boolean = false,
        val art: Bitmap? = null,
    )

    companion object {
        private const val CHANNEL_ID = "toomu_video_background"
        private const val NOTIFICATION_ID = 7302

        @Volatile var state = State()
        @Volatile private var instance: VideoBackgroundService? = null

        val running: Boolean get() = instance != null

        /** Pushes [state] to the running service (no-op if not running). */
        fun refresh() {
            instance?.publish()
        }
    }

    private var session: MediaSession? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        session = MediaSession(this, "ToomuVideo").apply {
            setCallback(object : MediaSession.Callback() {
                override fun onPlay() = send("play")
                override fun onPause() = send("pause")
                override fun onSeekTo(pos: Long) = send("seek:$pos")
                override fun onSkipToNext() = send("next")
                override fun onSkipToPrevious() = send("previous")
                override fun onFastForward() = send("forward")
                override fun onRewind() = send("rewind")
                override fun onStop() {
                    send("stop")
                    stopSelf()
                }
            })
            isActive = true
        }
        instance = this
    }

    private fun send(action: String) {
        VideoMediaBridge.listener?.invoke(action)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            val notification = publish()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            // Not allowed to start from the background right now; nothing to keep alive.
            stopSelf()
        }
        return START_NOT_STICKY
    }

    /** Updates the media session + notification from [state]. */
    private fun publish(): Notification {
        val s = state
        val session = session!!
        session.setMetadata(
            MediaMetadata.Builder()
                .putString(MediaMetadata.METADATA_KEY_TITLE, s.title)
                .putString(MediaMetadata.METADATA_KEY_ARTIST, s.subtitle)
                .putLong(MediaMetadata.METADATA_KEY_DURATION, s.durationMs)
                .apply { s.art?.let { putBitmap(MediaMetadata.METADATA_KEY_ART, it) } }
                .build()
        )
        var actions = PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or
            PlaybackState.ACTION_PLAY_PAUSE or PlaybackState.ACTION_SEEK_TO or
            PlaybackState.ACTION_STOP or PlaybackState.ACTION_SKIP_TO_PREVIOUS or
            PlaybackState.ACTION_FAST_FORWARD or PlaybackState.ACTION_REWIND
        if (s.hasNext) actions = actions or PlaybackState.ACTION_SKIP_TO_NEXT
        session.setPlaybackState(
            PlaybackState.Builder()
                .setActions(actions)
                .setState(
                    if (s.playing) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
                    s.positionMs,
                    if (s.playing) s.speed else 0f,
                    SystemClock.elapsedRealtime(),
                )
                .build()
        )

        val notification = build(s, session.sessionToken)
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, notification)
        return notification
    }

    private fun build(s: State, token: MediaSession.Token): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Video background play", NotificationManager.IMPORTANCE_LOW)
                    .apply { setShowBadge(false) }
            )
        }
        val open = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        // Android 13+ draws the controls from the session; older versions
        // use these standard transport buttons.
        fun action(icon: Int, label: String, act: String, code: Int) =
            Notification.Action.Builder(Icon.createWithResource(this, icon), label,
                VideoMediaBridge.pending(this, act, code)).build()

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION") Notification.Builder(this)
        }
        return builder
            .setSmallIcon(R.drawable.ic_stat_toomu)
            .setColor(0xFF7C4DFF.toInt())
            .setContentTitle(s.title)
            .setContentText(s.subtitle)
            .apply { s.art?.let { setLargeIcon(it) } }
            .setContentIntent(open)
            .setDeleteIntent(VideoMediaBridge.pending(this, VideoMediaBridge.ACTION_STOP, 15))
            .setOngoing(s.playing)
            .setShowWhen(false)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .addAction(action(android.R.drawable.ic_media_previous, "Previous", VideoMediaBridge.ACTION_PREVIOUS, 11))
            .addAction(
                if (s.playing) action(android.R.drawable.ic_media_pause, "Pause", VideoMediaBridge.ACTION_PLAY_PAUSE, 12)
                else action(android.R.drawable.ic_media_play, "Play", VideoMediaBridge.ACTION_PLAY_PAUSE, 12)
            )
            .addAction(action(android.R.drawable.ic_media_next, "Next", VideoMediaBridge.ACTION_NEXT, 13))
            .setStyle(Notification.MediaStyle().setMediaSession(token).setShowActionsInCompactView(0, 1, 2))
            .build()
    }

    override fun onDestroy() {
        instance = null
        session?.isActive = false
        session?.release()
        session = null
        super.onDestroy()
    }
}

/** Decodes artwork bytes from Dart (null if missing or broken). */
internal fun decodeArt(bytes: ByteArray?): Bitmap? =
    bytes?.let { android.graphics.BitmapFactory.decodeByteArray(it, 0, it.size) }
