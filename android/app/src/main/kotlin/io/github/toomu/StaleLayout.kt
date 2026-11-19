package io.github.toomu

import kotlin.math.abs

/**
 * Some phones (Realme / ColorOS) turned the window to landscape but left Flutter's view at its
 * upright size: the app drawn in the left ~45% of the screen, the rest blank. MainActivity checks
 * after each turn and lays the view out again when it doesn't fill the window.
 */
object StaleLayout {
    fun isStale(viewWidth: Int, viewHeight: Int, windowWidth: Int, windowHeight: Int): Boolean {
        if (windowWidth <= 0 || windowHeight <= 0 || viewWidth <= 0 || viewHeight <= 0) return false
        return abs(viewWidth - windowWidth) > 2 || abs(viewHeight - windowHeight) > 2
    }
}
