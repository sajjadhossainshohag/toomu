package com.example.toomu

import android.content.ComponentName
import android.content.Context
import android.media.MediaMetadata
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Bundle
import android.provider.Settings
import android.service.notification.NotificationListenerService

/**
 * Exists only so the user can grant "Notification access", which Android
 * requires before an app may read other apps' media sessions. Toomu never
 * reads notification contents; it only asks the media session what video
 * YouTube is playing (title, channel, duration) when the bubble is tapped.
 * While connected it also hosts the bubble, so no foreground notification is needed.
 */
class MediaNotificationListener : NotificationListenerService() {

    override fun onListenerConnected() {
        connected = true
        BubbleHost.sync(this)
    }

    override fun onListenerDisconnected() {
        connected = false
        BubbleHost.sync(this)
    }

    companion object {
        @Volatile var connected = false
            private set

        fun hasAccess(context: Context): Boolean {
            val enabled = Settings.Secure.getString(context.contentResolver, "enabled_notification_listeners")
            return enabled?.contains(context.packageName) == true
        }

        /**
         * Whether [packages] has a video open (playing, paused or loading:
         * the watch page or its mini player); null without Notification
         * access (then it can't be known). Feeds, search and Shorts publish
         * no media session.
         */
        fun hasVideoOpen(context: Context, packages: Set<String>): Boolean? {
            if (!hasAccess(context)) return null
            val manager = context.getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
            val sessions = try {
                manager.getActiveSessions(ComponentName(context, MediaNotificationListener::class.java))
            } catch (e: SecurityException) {
                return null
            }
            return sessions.any { session ->
                session.packageName in packages && session.metadata != null &&
                    when (session.playbackState?.state) {
                        PlaybackState.STATE_PLAYING, PlaybackState.STATE_PAUSED,
                        PlaybackState.STATE_BUFFERING, PlaybackState.STATE_CONNECTING -> true
                        else -> false
                    }
            }
        }

        /**
         * What [packages] is playing right now, as {title, artist, durationMs,
         * mediaId}; null without access or when nothing is playing.
         */
        fun nowPlaying(context: Context, packages: Set<String>): Bundle? {
            if (!hasAccess(context)) return null
            val manager = context.getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
            val sessions = try {
                manager.getActiveSessions(ComponentName(context, MediaNotificationListener::class.java))
            } catch (e: SecurityException) {
                return null
            }
            val session = sessions.firstOrNull { it.packageName in packages } ?: return null
            val metadata = session.metadata ?: return null
            val title = metadata.getString(MediaMetadata.METADATA_KEY_TITLE)
                ?: metadata.getString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE)
                ?: return null
            return Bundle().apply {
                putString("title", title)
                putString(
                    "artist",
                    metadata.getString(MediaMetadata.METADATA_KEY_ARTIST)
                        ?: metadata.getString(MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE),
                )
                putLong("durationMs", metadata.getLong(MediaMetadata.METADATA_KEY_DURATION))
                putString("mediaId", metadata.getString(MediaMetadata.METADATA_KEY_MEDIA_ID))
            }
        }
    }
}
