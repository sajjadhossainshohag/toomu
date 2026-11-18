package io.github.toomu

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

/**
 * Regression tests for downloads failing at the merge step and starting
 * over: a restart right after the library unzipped its packages left
 * 0-byte libraries (`CANNOT LINK EXECUTABLE "libaria2c.so": ... "libgmp.so"
 * >= file size: 0`, and yt-dlp finding no ffmpeg to merge with).
 */
class UnpackedPackagesTest {

    @get:Rule val tmp = TemporaryFolder()

    private lateinit var root: File
    private lateinit var packages: UnpackedPackages

    @Before
    fun setUp() {
        root = tmp.newFolder("packages")
        packages = UnpackedPackages(root)
    }

    private fun file(path: String, bytes: Int = 4096) =
        File(root, path).apply { parentFile!!.mkdirs(); writeBytes(ByteArray(bytes) { 1 }) }

    /** A package as the library unzips it, everything whole. */
    private fun healthy(name: String) {
        file("$name/usr/lib/libz.so")
        file("$name/usr/lib/libx264.so.164")
        file("$name/usr/bin/$name")
        file("$name/usr/lib/python3.12/email/mime/__init__.py", bytes = 0)
    }

    @Test
    fun `ffmpeg with an empty library is deleted so the library unzips it again`() {
        healthy("ffmpeg")
        healthy("python")
        file("ffmpeg/usr/lib/libgmp.so", bytes = 0)

        assertEquals(listOf("ffmpeg"), packages.repair())
        assertFalse(File(root, "ffmpeg").exists())
        assertTrue("whole packages are kept", File(root, "python").exists())
    }

    @Test
    fun `versioned library names count`() {
        healthy("ffmpeg")
        file("ffmpeg/usr/lib/libavutil.so.59.39.100", bytes = 0)

        assertEquals(listOf("ffmpeg"), packages.repair())
    }

    @Test
    fun `an empty program counts`() {
        healthy("aria2c")
        file("aria2c/usr/bin/aria2c", bytes = 0)

        assertEquals(listOf("aria2c"), packages.repair())
    }

    @Test
    fun `whole packages are left alone, empty python sources included`() {
        healthy("python")
        healthy("ffmpeg")
        file("python/usr/lib/python3.12/__pycache__/secrets.cpython-312.pyc", bytes = 0)
        file("ffmpeg/usr/lib/glib-2.0/include/glibconfig.h", bytes = 0)

        assertEquals(emptyList<String>(), packages.repair())
        assertTrue(File(root, "python").exists())
        assertTrue(File(root, "ffmpeg").exists())
    }

    @Test
    fun `no packages folder yet (first launch) is fine`() {
        assertEquals(emptyList<String>(), UnpackedPackages(File(root, "missing")).repair())
    }

    @Test
    fun `snapshot shows when a package was unzipped`() {
        healthy("python")
        val before = packages.snapshot()
        assertEquals(before, packages.snapshot())

        healthy("ffmpeg")
        assertNotEquals(before, packages.snapshot())
    }

    @Test
    fun `empty binary rule`() {
        assertTrue(UnpackedPackages.isEmptyBinary(file("p/usr/lib/libgmp.so", 0)))
        assertFalse(UnpackedPackages.isEmptyBinary(file("p/usr/lib/libgmp2.so", 10)))
        assertFalse(UnpackedPackages.isEmptyBinary(file("p/usr/lib/__init__.py", 0)))
        assertFalse(UnpackedPackages.isEmptyBinary(file("p/usr/lib/x.pyc", 0)))
        assertFalse(UnpackedPackages.isEmptyBinary(File(root, "p/usr/lib")))
    }
}
