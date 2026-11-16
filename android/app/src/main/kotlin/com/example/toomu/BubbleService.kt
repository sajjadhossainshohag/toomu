package com.example.toomu

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.provider.Settings

class BubbleService : Service() {

    companion object {
        const val ACTION_STOP = "com.example.toomu.BUBBLE_STOP"
        const val ACTION_BUBBLE_TAP = "com.example.toomu.BUBBLE_TAP"
        private const val CHANNEL_ID = "toomu_bubble"
        private const val NOTIFICATION_ID = 7301

        /** Apps the bubble appears over. */
        val TARGETS = setOf(
            "com.google.android.youtube",
            "com.google.android.apps.youtube.music",
            "app.revanced.android.youtube",
            "app.rvx.android.youtube",
        )

        @Volatile var instance: BubbleService? = null
            private set

        fun canDrawOverlays(context: Context) =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(context)

        fun hasUsageAccess(context: Context): Boolean {
            val ops = context.getSystemService(Context.APP_OPS_SERVICE) as android.app.AppOpsManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ops.unsafeCheckOpNoThrow(
                    android.app.AppOpsManager.OPSTR_GET_USAGE_STATS,
                    android.os.Process.myUid(), context.packageName,
                )
            } else {
                @Suppress("DEPRECATION")
                ops.checkOpNoThrow(
                    android.app.AppOpsManager.OPSTR_GET_USAGE_STATS,
                    android.os.Process.myUid(), context.packageName,
                )
            }
            return mode == android.app.AppOpsManager.MODE_ALLOWED
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            BubbleHost.setWanted(this, false)
            return START_NOT_STICKY
        }
        // A background restart (START_STICKY) may not be allowed to become a
        // foreground service on Android 12+; stop quietly instead of crashing.
        // Toomu restarts it the next time the app opens.
        try {
            startInForeground()
        } catch (e: Exception) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (BubbleHost.where(this) != BubbleHost.Where.SERVICE) {
            stopSelf()
            return START_NOT_STICKY
        }
        instance = this
        BubbleHost.show(this)
        return START_STICKY
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        if (!MediaNotificationListener.connected) BubbleHost.hide()
        super.onDestroy()
    }

    private fun startInForeground() {
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Floating download button", NotificationManager.IMPORTANCE_MIN)
                    .apply { setShowBadge(false) }
            )
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), flags)
        val stop = PendingIntent.getService(
            this, 1, Intent(this, BubbleService::class.java).setAction(ACTION_STOP), flags,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION") Notification.Builder(this)
        }
        val notification = builder
            .setSmallIcon(R.drawable.ic_stat_toomu)
            .setColor(0xFF7C4DFF.toInt())
            .setContentTitle("Download button is on")
            .setContentText("Shows over YouTube. Tap to open Toomu.")
            .setContentIntent(open)
            .setOngoing(true)
            .addAction(Notification.Action.Builder(null, "Turn off", stop).build())
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }
}
