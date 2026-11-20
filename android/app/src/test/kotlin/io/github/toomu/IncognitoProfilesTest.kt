package io.github.toomu

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class IncognitoProfilesTest {
    @Test
    fun `old incognito sessions are deleted, never normal tabs' profile or the session in use`() {
        val all = listOf("Default", "incognito-100", "incognito-200", "other")
        assertEquals(listOf("incognito-100"), IncognitoProfiles.leftovers(all, current = "incognito-200"))
    }

    @Test
    fun `only incognito names are accepted`() {
        assertTrue(IncognitoProfiles.isIncognito("incognito-1732100000"))
        assertFalse(IncognitoProfiles.isIncognito("Default"))
        assertFalse(IncognitoProfiles.isIncognito("incognito-"))
    }
}
