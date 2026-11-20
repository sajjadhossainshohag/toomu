package io.github.toomu

import kotlin.math.abs

/**
 * Some phones (Realme / ColorOS) turned the window to landscape but left Flutter's view at its
 * upright size: the app drawn in the left ~45% of the screen, the rest blank. MainActivity checks
 * after each turn and lays the view out again when it doesn't fill the window.
 *
 * The whole view tree (android.R.id.content too) can keep the old size, so the view is compared
 * with the window's real bounds (WindowMetrics) and with the orientation the phone reports.
 */
object StaleLayout {
    fun isStale(viewWidth: Int, viewHeight: Int, windowWidth: Int, windowHeight: Int): Boolean {
        if (windowWidth <= 0 || windowHeight <= 0 || viewWidth <= 0 || viewHeight <= 0) return false
        return abs(viewWidth - windowWidth) > 2 || abs(viewHeight - windowHeight) > 2
    }

    /** The view's shape disagrees with the phone's orientation (a square-ish view never does). */
    fun wrongShape(viewWidth: Int, viewHeight: Int, landscape: Boolean): Boolean {
        if (viewWidth <= 0 || viewHeight <= 0 || abs(viewWidth - viewHeight) <= 2) return false
        return (viewWidth > viewHeight) != landscape
    }

    /** Window bounds of 0 mean unknown (before Android 11). */
    fun needsLayout(viewWidth: Int, viewHeight: Int, windowWidth: Int, windowHeight: Int, landscape: Boolean): Boolean =
        isStale(viewWidth, viewHeight, windowWidth, windowHeight) || wrongShape(viewWidth, viewHeight, landscape)
}
