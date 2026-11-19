package io.github.toomu

import android.content.pm.ActivityInfo
import org.junit.Assert.assertEquals
import org.junit.Test

class PlayerOrientationTest {
    @Test
    fun `youtube player turns to landscape when auto-rotate is on`() {
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_SENSOR, PlayerOrientation.forAutoRotate(true))
    }

    @Test
    fun `player stays upright when the phone's auto-rotate is off`() {
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_PORTRAIT, PlayerOrientation.forAutoRotate(false))
    }
}
