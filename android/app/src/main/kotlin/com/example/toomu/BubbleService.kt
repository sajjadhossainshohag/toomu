package com.example.toomu

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.ImageView
import kotlin.math.abs

/**
 * Floating download bubble shown over the YouTube app (1DM/Snaptube style).
 *
 * Android doesn't let us add buttons inside another app, so this draws a
 * small overlay ("Display over other apps") and uses "Usage access" to see
 * which app is in front: the bubble shows only while YouTube is.
 * Tapping it opens Toomu, which reads the copied link and opens the
 * download sheet.
 */
class BubbleService : Service() {

    companion object {
        const val ACTION_STOP = "com.example.toomu.BUBBLE_STOP"
        const val ACTION_BUBBLE_TAP = "com.example.toomu.BUBBLE_TAP"
        private const val CHANNEL_ID = "toomu_bubble"
        private const val NOTIFICATION_ID = 7301
        private const val POLL_MS = 1000L
        private const val PREFS = "toomu_bubble"

        /** Apps the bubble appears over. */
        val TARGETS = setOf(
            "com.google.android.youtube",
            "com.google.android.apps.youtube.music",
            "app.revanced.android.youtube",
            "app.rvx.android.youtube",
        )

        @Volatile var running = false
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

    private val handler = Handler(Looper.getMainLooper())
    private lateinit var windowManager: WindowManager
    private var bubble: ImageView? = null
    private lateinit var params: WindowManager.LayoutParams
    private var foregroundApp: String? = null
    private var lastQuery = 0L

    private val poll = object : Runnable {
        override fun run() {
            updateForegroundApp()
            // Over YouTube, only while a video is open (its watch page or
            // mini player) — known with Notification access; without it,
            // on every YouTube screen.
            val show = foregroundApp in TARGETS &&
                MediaNotificationListener.hasVideoOpen(this@BubbleService, TARGETS) != false
            bubble?.visibility = if (show) View.VISIBLE else View.GONE
            handler.postDelayed(this, POLL_MS)
        }
    }

    /** No polling while the screen is off (nothing to show it over). */
    private val screen = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            handler.removeCallbacks(poll)
            if (intent.action == Intent.ACTION_SCREEN_ON) {
                lastQuery = System.currentTimeMillis() - 60_000
                handler.post(poll)
            }
        }
    }
    private var screenReceiverOn = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (!canDrawOverlays(this) || !hasUsageAccess(this)) {
            stopSelf()
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
        if (bubble == null) addBubble()
        running = true
        handler.removeCallbacks(poll)
        lastQuery = System.currentTimeMillis() - 60_000
        handler.post(poll)
        if (!screenReceiverOn) {
            registerReceiver(screen, IntentFilter().apply {
                addAction(Intent.ACTION_SCREEN_OFF)
                addAction(Intent.ACTION_SCREEN_ON)
            })
            screenReceiverOn = true
        }
        return START_STICKY
    }

    override fun onDestroy() {
        running = false
        handler.removeCallbacks(poll)
        if (screenReceiverOn) runCatching { unregisterReceiver(screen) }
        screenReceiverOn = false
        bubble?.let { runCatching { windowManager.removeView(it) } }
        bubble = null
        super.onDestroy()
    }

    // ------------------------------------------------------------------ bubble

    private fun dp(v: Float) =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, resources.displayMetrics).toInt()

    private fun addBubble() {
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        val size = dp(56f)
        val view = ImageView(this).apply {
            setImageResource(R.drawable.ic_bubble_download)
            setBackgroundResource(R.drawable.bubble_background)
            val pad = dp(15f)
            setPadding(pad, pad, pad, pad)
            elevation = dp(6f).toFloat()
            contentDescription = "Download with Toomu"
            visibility = View.GONE
        }
        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        val metrics = resources.displayMetrics
        @Suppress("DEPRECATION")
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else WindowManager.LayoutParams.TYPE_PHONE
        params = WindowManager.LayoutParams(
            size, size, type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = prefs.getInt("x", metrics.widthPixels - size - dp(12f))
            y = prefs.getInt("y", (metrics.heightPixels * 0.42).toInt())
        }
        view.setOnTouchListener(DragListener(size))
        windowManager.addView(view, params)
        bubble = view
    }

    /** Drag anywhere, snap to the nearest side; a tap opens Toomu. */
    private inner class DragListener(private val size: Int) : View.OnTouchListener {
        private val slop = ViewConfiguration.get(this@BubbleService).scaledTouchSlop
        private var downX = 0f
        private var downY = 0f
        private var startX = 0
        private var startY = 0
        private var moved = false

        override fun onTouch(v: View, e: MotionEvent): Boolean {
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = e.rawX; downY = e.rawY
                    startX = params.x; startY = params.y
                    moved = false
                    v.animate().scaleX(0.9f).scaleY(0.9f).setDuration(80).start()
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = e.rawX - downX
                    val dy = e.rawY - downY
                    if (!moved && (abs(dx) > slop || abs(dy) > slop)) moved = true
                    if (moved) {
                        params.x = startX + dx.toInt()
                        params.y = startY + dy.toInt()
                        windowManager.updateViewLayout(v, params)
                    }
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    v.animate().scaleX(1f).scaleY(1f).setDuration(80).start()
                    if (moved) {
                        val width = resources.displayMetrics.widthPixels
                        params.x = if (params.x + size / 2 < width / 2) dp(8f) else width - size - dp(8f)
                        params.y = params.y.coerceIn(dp(24f), resources.displayMetrics.heightPixels - size - dp(48f))
                        windowManager.updateViewLayout(v, params)
                        getSharedPreferences(PREFS, MODE_PRIVATE).edit()
                            .putInt("x", params.x).putInt("y", params.y).apply()
                    } else if (e.actionMasked == MotionEvent.ACTION_UP) {
                        openToomu()
                    }
                }
            }
            return true
        }
    }

    /** Allowed from the background because this app holds an overlay window. */
    private fun openToomu() {
        val intent = Intent(this, MainActivity::class.java).apply {
            action = ACTION_BUBBLE_TAP
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            // What YouTube is playing (needs Notification access); lets Toomu
            // open the download sheet without the user copying a link.
            MediaNotificationListener.nowPlaying(this@BubbleService, TARGETS)?.let { putExtras(it) }
        }
        startActivity(intent)
    }

    // ------------------------------------------------------- foreground app

    private fun updateForegroundApp() {
        val usm = getSystemService(USAGE_STATS_SERVICE) as UsageStatsManager
        val now = System.currentTimeMillis()
        val events = usm.queryEvents(lastQuery, now)
        val event = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            @Suppress("DEPRECATION")
            if (event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND) {
                foregroundApp = event.packageName
            }
        }
        lastQuery = now - 500 // small overlap so no event is missed
    }

    // ---------------------------------------------------------- notification

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
