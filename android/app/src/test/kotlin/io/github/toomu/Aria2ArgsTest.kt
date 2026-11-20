package io.github.toomu

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class Aria2ArgsTest {
    private fun downloaderArgs(n: Int) = Aria2Args.of(n, "/ca.pem").let { it[it.indexOf("--downloader-args") + 1] }

    @Test
    fun `a download paused in its first minute shows its bytes - aria2c saves its progress every second`() {
        // The paused size comes from aria2c's control file; by default it is saved only every 60 s, so a pause
        // sooner showed the gappy file's length (near the end of the file).
        assertTrue(downloaderArgs(8).contains("--auto-save-interval=1"))
    }

    @Test
    fun `connections stay between 2 and 16`() {
        assertTrue(downloaderArgs(1).startsWith("aria2c:-x 2 -s 2 "))
        assertTrue(downloaderArgs(40).startsWith("aria2c:-x 16 -s 16 "))
        assertEquals("libaria2c.so", Aria2Args.of(8, "/ca.pem")[1])
    }
}
