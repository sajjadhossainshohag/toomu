package io.github.toomu

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper

/**
 * Routes video-control buttons from the picture-in-picture window and the
 * background-play media controls to the player in Dart (via MainActivity).
 */
object VideoMediaBridge {
    const val ACTION_PLAY_PAUSE = "io.github.toomu.video.PLAY_PAUSE"
    const val ACTION_REWIND = "io.github.toomu.video.REWIND"
    const val ACTION_FORWARD = "io.github.toomu.video.FORWARD"
    const val ACTION_STOP = "io.github.toomu.video.STOP"
    const val ACTION_NEXT = "io.github.toomu.video.NEXT"
    const val ACTION_PREVIOUS = "io.github.toomu.video.PREVIOUS"

    /** Set by MainActivity while a Flutter engine is attached. */
    @Volatile var listener: ((String) -> Unit)? = null

    private val main = Handler(Looper.getMainLooper())

    fun dispatch(action: String) {
        val name = when (action) {
            ACTION_PLAY_PAUSE -> "playPause"
            ACTION_REWIND -> "rewind"
            ACTION_FORWARD -> "forward"
            ACTION_STOP -> "stop"
            ACTION_NEXT -> "next"
            ACTION_PREVIOUS -> "previous"
            else -> return
        }
        main.post { listener?.invoke(name) }
    }

    /** Explicit broadcast to [VideoActionReceiver] (works from system UI). */
    fun pending(context: Context, action: String, requestCode: Int): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            requestCode,
            Intent(context, VideoActionReceiver::class.java).setAction(action),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
}

class VideoActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action == VideoMediaBridge.ACTION_STOP) {
            context.stopService(Intent(context, VideoBackgroundService::class.java))
        }
        VideoMediaBridge.dispatch(action)
    }
}
