package com.example.toomu

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.io.IOException

/**
 * Regression tests for "yt-dlp finished but the file is missing": an update
 * interrupted by a restart left yt-dlp as a 0-byte file, which Python runs
 * as a no-op that exits 0, so every download "succeeded" with no file.
 */
class YtDlpBinaryFilesTest {

    @get:Rule val tmp = TemporaryFolder()

    private lateinit var dir: File
    private lateinit var files: YtDlpBinaryFiles

    @Before
    fun setUp() {
        dir = tmp.newFolder("yt-dlp")
        files = YtDlpBinaryFiles(dir, "yt-dlp")
    }

    /** A plausible yt-dlp: over the size limit, recognisable content. */
    private fun whole(seed: Int) = ByteArray(YtDlpBinaryFiles.MIN_BYTES.toInt() + 1024) { (it * 31 + seed).toByte() }

    // ------------------------------------------------------------- repair

    @Test
    fun `empty binary left by an interrupted update is deleted so the bundled copy is unpacked`() {
        files.binary.writeBytes(ByteArray(0))

        assertTrue(files.repair())
        assertFalse("library re-extracts only when the file is missing", files.binary.exists())
    }

    @Test
    fun `truncated binary is treated as broken too`() {
        files.binary.writeBytes(ByteArray(500_000))

        assertTrue(files.repair())
        assertFalse(files.binary.exists())
    }

    @Test
    fun `broken binary is restored from a whole backup`() {
        val old = whole(1)
        files.binary.writeBytes(ByteArray(0))
        files.backup.writeBytes(old)

        assertTrue(files.repair())
        assertArrayEquals(old, files.binary.readBytes())
        assertFalse(files.backup.exists())
    }

    @Test
    fun `a broken backup is not restored`() {
        files.binary.writeBytes(ByteArray(0))
        files.backup.writeBytes(ByteArray(0))

        assertTrue(files.repair())
        assertFalse(files.binary.exists())
        assertFalse(files.backup.exists())
    }

    @Test
    fun `a whole binary is left alone`() {
        val good = whole(2)
        files.binary.writeBytes(good)

        assertFalse(files.repair())
        assertArrayEquals(good, files.binary.readBytes())
    }

    @Test
    fun `a missing binary is left for the library to unpack`() {
        assertFalse(files.repair())
        assertFalse(files.binary.exists())
    }

    @Test
    fun `leftover partial copies are cleaned up`() {
        files.binary.writeBytes(whole(3))
        File(dir, "yt-dlp.part").writeBytes(ByteArray(10))
        File(dir, "yt-dlp.bak.part").writeBytes(ByteArray(10))

        files.repair()

        assertEquals(listOf("yt-dlp"), dir.list()!!.sorted())
    }

    // -------------------------------------------------------- durableCopy

    @Test
    fun `durable copy replaces the whole file and leaves no partial copy`() {
        val new = whole(4)
        val source = tmp.newFile("download").apply { writeBytes(new) }
        files.binary.writeBytes(whole(5))

        files.durableCopy(source, files.binary)

        assertArrayEquals(new, files.binary.readBytes())
        assertEquals(listOf("yt-dlp"), dir.list()!!.sorted())
    }

    @Test
    fun `a failed copy keeps the working binary intact`() {
        val good = whole(6)
        files.binary.writeBytes(good)

        try {
            files.durableCopy(File(tmp.root, "missing"), files.binary)
            fail("expected the copy to fail")
        } catch (_: IOException) {
        }

        assertArrayEquals(good, files.binary.readBytes())
        assertFalse(File(dir, "yt-dlp.part").exists())
    }
}
