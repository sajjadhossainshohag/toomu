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
    fun `a view that fills the window is left alone`() {
        assertFalse(StaleLayout.isStale(2400, 1080, 2400, 1080))
        assertFalse(StaleLayout.isStale(2399, 1080, 2400, 1080)) // rounding
    }

    @Test
    fun `nothing is measured yet`() {
        assertFalse(StaleLayout.isStale(0, 0, 2400, 1080))
        assertFalse(StaleLayout.isStale(1080, 2400, 0, 0))
    }
}
