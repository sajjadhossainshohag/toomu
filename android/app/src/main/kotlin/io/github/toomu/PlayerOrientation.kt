package io.github.toomu

import android.content.pm.ActivityInfo

/**
 * The video player's screen orientation while it follows the phone. Flutter's "follow the phone"
 * (SCREEN_ORIENTATION_USER) left YouTube videos upright on some phones even with auto-rotate on, so
 * the player reads the phone's auto-rotate setting itself: on, the sensor turns the screen
 * (landscape both ways, upright); off, it stays upright like the rest of the phone.
 *
 * The rotate button holds its choice (like YouTube) until the phone is physically turned the same
 * way; then, with auto-rotate on, the screen follows the phone again.
 */
object PlayerOrientation {
    fun forAutoRotate(autoRotate: Boolean): Int =
        if (autoRotate) ActivityInfo.SCREEN_ORIENTATION_SENSOR else ActivityInfo.SCREEN_ORIENTATION_PORTRAIT

    fun locked(landscape: Boolean): Int =
        if (landscape) ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE else ActivityInfo.SCREEN_ORIENTATION_PORTRAIT

    /**
     * How the phone is held, from OrientationEventListener's degrees: within 30° of sideways is
     * landscape, within 30° of upright (or upside down) is portrait; in between, or lying flat (-1),
     * nothing.
     */
    fun physicalLandscape(degrees: Int): Boolean? {
        if (degrees < 0) return null
        val d = degrees % 180
        return when {
            d in 60..120 -> true
            d <= 30 || d >= 150 -> false
            else -> null
        }
    }

    fun releasesLock(lockedLandscape: Boolean, degrees: Int, autoRotate: Boolean): Boolean =
        autoRotate && physicalLandscape(degrees) == lockedLandscape
}
