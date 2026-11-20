package io.github.toomu

import android.content.pm.ActivityInfo
import android.view.WindowManager
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
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

    @Test
    fun `the rotate button holds its choice while the phone is held the other way`() {
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE, PlayerOrientation.locked(true))
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_PORTRAIT, PlayerOrientation.locked(false))
        // Full screen by the button, phone still upright: stays landscape.
        assertFalse(PlayerOrientation.releasesLock(lockedLandscape = true, degrees = 0, autoRotate = true))
    }

    @Test
    fun `watch page turns with the phone again after the rotate button was used`() {
        // Full screen by the button, then the phone is turned sideways: auto-rotate takes over again,
        // so turning it upright later goes back to the watch page.
        assertTrue(PlayerOrientation.releasesLock(lockedLandscape = true, degrees = 90, autoRotate = true))
        assertTrue(PlayerOrientation.releasesLock(lockedLandscape = true, degrees = 270, autoRotate = true))
        // Back upright by the button while held sideways, then held upright: turning sideways works again.
        assertTrue(PlayerOrientation.releasesLock(lockedLandscape = false, degrees = 0, autoRotate = true))
        assertTrue(PlayerOrientation.releasesLock(lockedLandscape = false, degrees = 355, autoRotate = true))
    }

    @Test
    fun `with auto-rotate off the button's choice stays`() {
        assertFalse(PlayerOrientation.releasesLock(lockedLandscape = true, degrees = 90, autoRotate = false))
    }

    @Test
    fun `a phone held at an angle or lying flat says nothing`() {
        assertNull(PlayerOrientation.physicalLandscape(45))
        assertNull(PlayerOrientation.physicalLandscape(-1)) // ORIENTATION_UNKNOWN: flat on a table
        assertFalse(PlayerOrientation.releasesLock(lockedLandscape = true, degrees = 45, autoRotate = true))
        assertFalse(PlayerOrientation.releasesLock(lockedLandscape = false, degrees = -1, autoRotate = true))
    }

    @Test
    fun `the player turns at once like MX, the rest of the app keeps the normal turn`() {
        assertEquals(WindowManager.LayoutParams.ROTATION_ANIMATION_SEAMLESS, PlayerOrientation.rotationAnimation(26, playerOpen = true))
        assertEquals(WindowManager.LayoutParams.ROTATION_ANIMATION_SEAMLESS, PlayerOrientation.rotationAnimation(35, playerOpen = true))
        // Android 7 has no seamless turn: a jump cut, still at once.
        assertEquals(WindowManager.LayoutParams.ROTATION_ANIMATION_JUMPCUT, PlayerOrientation.rotationAnimation(24, playerOpen = true))
        assertEquals(WindowManager.LayoutParams.ROTATION_ANIMATION_ROTATE, PlayerOrientation.rotationAnimation(35, playerOpen = false))
    }
}
