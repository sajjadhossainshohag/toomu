package io.github.toomu

import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.ImageView
import kotlin.math.abs

object BubbleHost {
    enum class Where { NONE, LISTENER, SERVICE }

    const val PREFS = "toomu_bubble"
    private const val KEY_ON = "on"

    private var bubble: FloatingBubble? = null

    val showing get() = bubble != null

    fun where(wanted: Boolean, permitted: Boolean, listenerConnected: Boolean) = when {
        !wanted || !permitted -> Where.NONE
        // Android keeps a connected notification listener alive itself, so no foreground notification is needed.
        listenerConnected -> Where.LISTENER
        else -> Where.SERVICE
    }

    fun where(context: Context) = where(
        wanted = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY_ON, false),
        permitted = BubbleService.canDrawOverlays(context) && BubbleService.hasUsageAccess(context),
        listenerConnected = MediaNotificationListener.connected,
    )

    fun setWanted(context: Context, on: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(KEY_ON, on).apply()
        sync(context)
    }

    fun sync(context: Context) {
        val app = context.applicationContext
        val where = where(app)
        if (where != Where.SERVICE) BubbleService.instance?.stopSelf()
        when (where) {
            Where.NONE -> hide()
            Where.LISTENER -> show(app)
            Where.SERVICE -> if (BubbleService.instance == null) {
                val intent = Intent(app, BubbleService::class.java)
                // Starting it from the background (the listener just lost access) can be refused on
                // Android 12+; Toomu starts it again the next time the app opens.
                runCatching {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) app.startForegroundService(intent)
                    else app.startService(intent)
                }.onFailure { hide() }
            }
        }
    }

    fun show(context: Context) {
        if (bubble == null) bubble = FloatingBubble(context.applicationContext).also { it.show() }
    }

    fun hide() {
        bubble?.hide()
        bubble = null
    }
}

/**
 * Floating download bubble shown over the YouTube app (1DM/Snaptube style).
 *
 * Android doesn't let us add buttons inside another app, so this draws a
 * small overlay ("Display over other apps") and uses "Usage access" to see
 * which app is in front: the bubble shows only while YouTube is.
 * Tapping it opens Toomu, which reads the copied link and opens the
 * download sheet.
 */
class FloatingBubble(private val context: Context) {

    companion object {
        private const val POLL_MS = 1000L
    }

    private val handler = Handler(Looper.getMainLooper())
    private val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
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
            val show = foregroundApp in BubbleService.TARGETS &&
                MediaNotificationListener.hasVideoOpen(context, BubbleService.TARGETS) != false
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

    fun show() {
        addBubble()
        lastQuery = System.currentTimeMillis() - 60_000
        handler.post(poll)
        context.registerReceiver(screen, IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_SCREEN_ON)
        })
    }

    fun hide() {
        handler.removeCallbacks(poll)
        runCatching { context.unregisterReceiver(screen) }
        bubble?.let { runCatching { windowManager.removeView(it) } }
        bubble = null
    }

    private fun dp(v: Float) =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, context.resources.displayMetrics).toInt()

    private fun addBubble() {
        val size = dp(56f)
        val view = ImageView(context).apply {
            setImageResource(R.drawable.ic_bubble_download)
            setBackgroundResource(R.drawable.bubble_background)
            val pad = dp(15f)
            setPadding(pad, pad, pad, pad)
            elevation = dp(6f).toFloat()
            contentDescription = "Download with Toomu"
            visibility = View.GONE
        }
        val prefs = context.getSharedPreferences(BubbleHost.PREFS, Context.MODE_PRIVATE)
        val metrics = context.resources.displayMetrics
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
        private val slop = ViewConfiguration.get(context).scaledTouchSlop
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
                        val metrics = context.resources.displayMetrics
                        params.x = if (params.x + size / 2 < metrics.widthPixels / 2) dp(8f) else metrics.widthPixels - size - dp(8f)
                        params.y = params.y.coerceIn(dp(24f), metrics.heightPixels - size - dp(48f))
                        windowManager.updateViewLayout(v, params)
                        context.getSharedPreferences(BubbleHost.PREFS, Context.MODE_PRIVATE).edit()
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
        val intent = Intent(context, MainActivity::class.java).apply {
            action = BubbleService.ACTION_BUBBLE_TAP
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            // What YouTube is playing (needs Notification access); lets Toomu
            // open the download sheet without the user copying a link.
            MediaNotificationListener.nowPlaying(context, BubbleService.TARGETS)?.let { putExtras(it) }
        }
        context.startActivity(intent)
    }

    private fun updateForegroundApp() {
        val usm = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
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
}
