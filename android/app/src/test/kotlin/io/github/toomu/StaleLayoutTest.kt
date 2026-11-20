package io.github.toomu

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class StaleLayoutTest {
    @Test
    fun `landscape player drawn at the upright size is caught`() {
        // RMX3461 after the rotate button: a 1080x2400 view in a 2400x1080 window.
        assertTrue(StaleLayout.isStale(1080, 2400, 2400, 1080))
    }

    @Test
    fun `half-screen player after rotate is caught when the whole view tree kept the upright size`() {
        // Realme: the content view was 1080x2400 too, so comparing with it saw nothing wrong. The phone
        // says landscape (and the window is 2400x1080), so the upright view is caught.
        assertTrue(StaleLayout.needsLayout(1080, 2400, windowWidth = 0, windowHeight = 0, landscape = true))
        assertTrue(StaleLayout.needsLayout(1080, 2400, windowWidth = 2400, windowHeight = 1080, landscape = true))
        // And back upright with a view still lying down.
        assertTrue(StaleLayout.needsLayout(2400, 1080, windowWidth = 0, windowHeight = 0, landscape = false))
    }

    @Test
    fun `picture stuck in a corner after turning is caught when only Flutter's surface kept the old size`() {
        // Emulator (and Realme) after turning: window, content and FlutterView all 1080x2400, the
        // FlutterSurfaceView inside still 2400x1080, so the app drew sideways in the top-left corner.
        assertTrue(StaleLayout.surfaceNeedsLayout(2400, 1080, viewWidth = 1080, viewHeight = 2400))
        assertTrue(StaleLayout.surfaceNeedsLayout(1080, 2400, viewWidth = 2400, viewHeight = 1080))
        assertFalse(StaleLayout.surfaceNeedsLayout(1080, 2400, viewWidth = 1080, viewHeight = 2400))
    }

    @Test
    fun `half-screen picture after turning, a surface pinned to its old size is set back to fill the view`() {
        // Emulator log: "surface 1080x2400 (params 1080x2400 ...)" in a 2400x1080 view. Fixed layout params put the
        // surface back to its old size on every layout pass, so laying it out again never helped.
        assertTrue(StaleLayout.paramsPinned(1080, 2400))
        assertTrue(StaleLayout.paramsPinned(-1, 2400))
        assertFalse(StaleLayout.paramsPinned(-1, -1)) // MATCH_PARENT both ways: it follows the view
    }

    @Test
    fun `a view that fills the window is left alone`() {
        assertFalse(StaleLayout.isStale(2400, 1080, 2400, 1080))
        assertFalse(StaleLayout.isStale(2399, 1080, 2400, 1080)) // rounding
        assertFalse(StaleLayout.needsLayout(2400, 1080, 2400, 1080, landscape = true))
        assertFalse(StaleLayout.needsLayout(1080, 2400, 1080, 2400, landscape = false))
    }

    @Test
    fun `a view a little smaller than the window (system bars, cutout) is left alone`() {
        assertFalse(StaleLayout.needsLayout(2280, 1080, windowWidth = 2400, windowHeight = 1080, landscape = true))
        assertFalse(StaleLayout.needsLayout(1080, 2274, windowWidth = 1080, windowHeight = 2400, landscape = false))
    }

    @Test
    fun `nothing is measured yet`() {
        assertFalse(StaleLayout.isStale(0, 0, 2400, 1080))
        assertFalse(StaleLayout.isStale(1080, 2400, 0, 0))
        assertFalse(StaleLayout.needsLayout(0, 0, 0, 0, landscape = true))
    }
}
