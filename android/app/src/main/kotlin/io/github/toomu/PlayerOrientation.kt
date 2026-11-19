package io.github.toomu

import android.content.pm.ActivityInfo

/**
 * The video player's screen orientation while it follows the phone. Flutter's "follow the phone"
 * (SCREEN_ORIENTATION_USER) left YouTube videos upright on some phones even with auto-rotate on, so
 * the player reads the phone's auto-rotate setting itself: on, the sensor turns the screen
 * (landscape both ways, upright); off, it stays upright like the rest of the phone.
 */
object PlayerOrientation {
    fun forAutoRotate(autoRotate: Boolean): Int =
        if (autoRotate) ActivityInfo.SCREEN_ORIENTATION_SENSOR else ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
}
