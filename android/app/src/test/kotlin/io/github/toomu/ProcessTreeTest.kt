package io.github.toomu

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ProcessTreeTest {
    @Test
    fun `pausing a download stops aria2c and ffmpeg too, not only yt-dlp`() {
        // yt-dlp (python, 100) started aria2c (101), which has a helper (102), and ffmpeg (103). The library's own
        // child kill (pstree + grep -P) never works on Android, so aria2c kept downloading after a pause.
        val parents = mapOf(100 to 50, 101 to 100, 102 to 101, 103 to 100, 200 to 50, 201 to 200)
        // Deepest first, so nothing is left without its parent while still running.
        assertEquals(listOf(102, 101, 103), ProcessTree.descendants(100, parents))
    }

    @Test
    fun `another download's processes are left alone`() {
        val parents = mapOf(100 to 50, 101 to 100, 200 to 50, 201 to 200)
        assertEquals(listOf(201), ProcessTree.descendants(200, parents))
        assertEquals(emptyList<Int>(), ProcessTree.descendants(300, parents))
    }

    @Test
    fun `the parent is read from proc stat, even with spaces or brackets in the name`() {
        assertEquals(1200, ProcessTree.parentOf("1234 (libaria2c.so) S 1200 1234 0 0 -1 4194560 3065"))
        assertEquals(7, ProcessTree.parentOf("55 (my (odd) name) R 7 55 0"))
        assertNull(ProcessTree.parentOf("garbage"))
    }

    @Test
    fun `the process id is found in the process's description`() {
        assertEquals(4321, ProcessTree.pidFromDescription("Process[pid=4321, hasExited=false]"))
        assertNull(ProcessTree.pidFromDescription("java.lang.ProcessImpl@1a2b"))
    }
}
