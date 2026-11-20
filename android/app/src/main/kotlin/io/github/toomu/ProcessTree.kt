package io.github.toomu

import java.io.File

/**
 * yt-dlp's child processes (aria2c, ffmpeg). Pausing a download ended only yt-dlp itself: the library's own
 * child kill runs `pstree -p <id> | grep -oP … | xargs kill`, with the download's id instead of a process id,
 * and Android has neither pstree nor grep -P. aria2c then kept downloading the rest of the file in the
 * background (network busy, phone warm, the paused size growing).
 */
object ProcessTree {
    /** All processes below [root], deepest first. */
    fun descendants(root: Int, parents: Map<Int, Int>): List<Int> {
        val children = parents.entries.groupBy({ it.value }, { it.key }).mapValues { (_, v) -> v.sorted() }
        val out = mutableListOf<Int>()
        fun walk(pid: Int, depth: Int) {
            if (depth > 32) return
            for (child in children[pid].orEmpty()) {
                walk(child, depth + 1)
                out += child
            }
        }
        walk(root, 0)
        return out
    }

    /** The parent pid from a /proc/<pid>/stat line ("pid (name) state ppid …"; the name may hold spaces). */
    fun parentOf(stat: String): Int? {
        val end = stat.lastIndexOf(')')
        if (end < 0) return null
        return stat.substring(end + 1).trim().split(' ').getOrNull(1)?.toIntOrNull()
    }

    fun pidFromDescription(description: String): Int? =
        Regex("""pid=(\d+)""").find(description)?.groupValues?.get(1)?.toIntOrNull()

    /** Parent of every process this app can see. */
    fun parentsNow(): Map<Int, Int> {
        val out = mutableMapOf<Int, Int>()
        for (dir in File("/proc").listFiles().orEmpty()) {
            val pid = dir.name.toIntOrNull() ?: continue
            val parent = try {
                parentOf(File(dir, "stat").readText())
            } catch (_: Exception) {
                null
            } ?: continue
            out[pid] = parent
        }
        return out
    }

    /** [process]'s pid: the field on Android's process class, else its description. */
    fun pidOf(process: Process): Int? {
        var c: Class<*>? = process.javaClass
        while (c != null) {
            try {
                val f = c.getDeclaredField("pid")
                f.isAccessible = true
                return (f.get(process) as? Number)?.toInt()
            } catch (_: Exception) {
                c = c.superclass
            }
        }
        return pidFromDescription(process.toString())
    }

    fun alive(pid: Int) = File("/proc/$pid").exists()
}
