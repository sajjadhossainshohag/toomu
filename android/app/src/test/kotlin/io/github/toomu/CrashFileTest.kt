package io.github.toomu

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** Android crashes are saved for the app's crash reporter in the shape Dart reads. */
class CrashFileTest {

    @get:Rule val tmp = TemporaryFolder()

    @Test
    fun `a crash is written as a native report with its message and stack`() {
        val dir = tmp.newFolder("crash_reports")
        val error = IllegalStateException("boom \"quoted\"\nnext line\t\\ end")
        val file = CrashFile.write(dir, error, 1700000000000)!!
        assertEquals("1700000000000-native.json", file.name)
        val text = file.readText()
        assertTrue(text.startsWith("""{"kind":"native","message":"java.lang.IllegalStateException: boom \"quoted\"\nnext line\t\\ end","""))
        assertTrue(text.contains("""\n\tat io.github.toomu.CrashFileTest"""))
        assertTrue(text.endsWith(""","time":1700000000000}"""))
        assertTrue("no raw line breaks", !text.contains('\n'))
    }

    @Test
    fun `control characters are escaped`() {
        assertEquals("\"a\\u0001b\"", CrashFile.quote("a\u0001b"))
    }

    @Test
    fun `a crash loop writes at most five files`() {
        val dir = tmp.newFolder("crash_reports")
        repeat(5) { CrashFile.write(dir, RuntimeException("x"), 1000L + it) }
        assertNull(CrashFile.write(dir, RuntimeException("x"), 2000L))
        assertEquals(5, dir.listFiles()!!.size)
    }
}
