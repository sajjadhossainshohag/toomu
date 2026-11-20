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
    fun `a view that fills the window is left alone`() {
        assertFalse(StaleLayout.isStale(2400, 1080, 2400, 1080))
        assertFalse(StaleLayout.isStale(2399, 1080, 2400, 1080)) // rounding
        assertFalse(StaleLayout.needsLayout(2400, 1080, 2400, 1080, landscape = true))
        assertFalse(StaleLayout.needsLayout(1080, 2400, 1080, 2400, landscape = false))
    }

    @Test
    fun `nothing is measured yet`() {
        assertFalse(StaleLayout.isStale(0, 0, 2400, 1080))
        assertFalse(StaleLayout.isStale(1080, 2400, 0, 0))
        assertFalse(StaleLayout.needsLayout(0, 0, 0, 0, landscape = true))
    }
}
