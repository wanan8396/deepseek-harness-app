package app.dsh.runtime

import android.os.Process
import android.os.SystemClock

/**
 * Where a start's time went, for one line in the runtime log once DSH listens (so a phone's
 * cold start can be read off its log or diagnostics bundle). Times are elapsedRealtime ms:
 * [processStart] is when this app process was forked (not the user tap).
 */
class StartupTimeline(private val processStart: Long?) {
    @Volatile private var requested = 0L
    @Volatile private var spawned = 0L
    @Volatile private var released = 0L

    fun requested(now: Long = SystemClock.elapsedRealtime()) {
        requested = now
        spawned = 0L
        released = 0L
    }

    /** Entry to DshProcess.start(), before Root selection and actual process creation. */
    fun launcherEntered(now: Long = SystemClock.elapsedRealtime()) {
        spawned = now
    }

    fun guestReleased(now: Long = SystemClock.elapsedRealtime()) {
        released = now
    }

    /** The log line for a start that just reached listening, or null without the earlier marks. */
    fun ready(now: Long = SystemClock.elapsedRealtime()): String? {
        if (requested == 0L || spawned == 0L || now < spawned) return null
        return line(processStart, requested, spawned, now, released)
    }

    companion object {
        fun forThisProcess() = StartupTimeline(runCatching { Process.getStartElapsedRealtime() }.getOrNull())

        /**
         * `app` (process start → start requested) is left out when the process was already running
         * before this start (a restart, or a start long after launch).
         */
        fun line(processStart: Long?, requested: Long, spawned: Long, ready: Long, released: Long = 0L): String {
            val parts = ArrayList<String>()
            if (processStart != null && processStart in 1..requested && requested - processStart < LAUNCH_WINDOW_MS) {
                parts += "app ${requested - processStart} ms"
            }
            parts += "prepare ${spawned - requested} ms"
            if (released in spawned..ready) {
                parts += "launcher ${released - spawned} ms"
                parts += "guest-to-listening ${ready - released} ms"
            } else {
                parts += "launcher-to-listening ${ready - spawned} ms"
            }
            return "[dsh-app] startup: ${parts.joinToString(", ")}"
        }

        private const val LAUNCH_WINDOW_MS = 30_000L
    }
}
