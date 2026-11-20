package io.github.toomu

import kotlin.math.abs

/**
 * Some phones (Realme / ColorOS) turned the window to landscape but left Flutter's view at its
 * upright size: the app drawn in the left ~45% of the screen, the rest blank. MainActivity checks
 * after each turn and lays the view out again when it doesn't fill the window.
 *
 * The view is compared with the shape of the window's real bounds (WindowMetrics) and the
 * orientation the phone reports, and Flutter's render surface inside it with the view.
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

    /**
     * The view lies the wrong way for the window (bounds of 0 mean unknown, before Android 11) or for
     * the phone's orientation. Only the shape counts: a view a little smaller than the window (system
     * bars, the camera cutout, the keyboard) is normal.
     */
    fun needsLayout(viewWidth: Int, viewHeight: Int, windowWidth: Int, windowHeight: Int, landscape: Boolean): Boolean {
        val windowKnown = windowWidth > 0 && windowHeight > 0 && abs(windowWidth - windowHeight) > 2
        return wrongShape(viewWidth, viewHeight, landscape) ||
            (windowKnown && wrongShape(viewWidth, viewHeight, windowWidth > windowHeight))
    }

    /**
     * Flutter's render surface (FlutterSurfaceView / FlutterTextureView) must fill FlutterView. After
     * a turn it sometimes kept the old size while every view around it was right: the app drawn
     * sideways in one corner, the window's white background around it.
     */
    fun surfaceNeedsLayout(surfaceWidth: Int, surfaceHeight: Int, viewWidth: Int, viewHeight: Int): Boolean =
        isStale(surfaceWidth, surfaceHeight, viewWidth, viewHeight)
}
