package io.github.toomu

import android.app.Application
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter

/**
 * Kotlin/Java crashes → a file in `files/crash_reports/` (what Dart's getApplicationSupportDirectory
 * returns), sent by the app's crash reporter on the next start once the user agreed
 * (`crash_report_service.dart`). Written before Android's own handler ends the process.
 */
object CrashFile {
    private const val MAX_STACK = 12_000
    private const val MAX_PENDING = 5

    fun install(app: Application) {
        val dir = File(app.filesDir, "crash_reports")
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            try {
                write(dir, error, System.currentTimeMillis())
            } catch (_: Throwable) {
                // never let the report hide the crash
            }
            previous?.uncaughtException(thread, error)
        }
    }

    /** The report file, or null when enough are already waiting. */
    fun write(dir: File, error: Throwable, now: Long): File? {
        dir.mkdirs()
        if ((dir.listFiles { f -> f.name.endsWith(".json") }?.size ?: 0) >= MAX_PENDING) return null
        val file = File(dir, "$now-native.json")
        file.writeText(json(error, now))
        return file
    }

    fun json(error: Throwable, now: Long): String {
        val trace = StringWriter().also { error.printStackTrace(PrintWriter(it)) }.toString()
        val stack = if (trace.length > MAX_STACK) trace.substring(0, MAX_STACK) else trace
        return """{"kind":"native","message":${quote(error.toString())},"stack":${quote(stack)},"time":$now}"""
    }

    /** A JSON string (org.json isn't available to unit tests). */
    fun quote(s: String): String {
        val out = StringBuilder("\"")
        for (c in s) {
            when (c) {
                '"' -> out.append("\\\"")
                '\\' -> out.append("\\\\")
                '\n' -> out.append("\\n")
                '\r' -> out.append("\\r")
                '\t' -> out.append("\\t")
                else -> if (c < ' ') out.append(String.format("\\u%04x", c.code)) else out.append(c)
            }
        }
        return out.append('"').toString()
    }
}

/** Toomu's Application: installs the crash file writer before anything else runs. */
class ToomuApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        CrashFile.install(this)
    }
}
