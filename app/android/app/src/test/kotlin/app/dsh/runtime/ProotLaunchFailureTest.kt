package app.dsh.runtime

import org.junit.Assert.*
import org.junit.Test

class ProotLaunchFailureTest {
    private val reported = listOf(
        "proot error: execve(\"/usr/bin/env\"): Permission denied",
        "proot error: execve(\"/usr/bin/env\"): Too many symbolic links encountered",
    )

    private fun classify(
        tail: List<String>,
        readyAt: Long? = null,
        exitCode: Int = 1,
        safe: Boolean = false,
    ) = CrashClassifier.classify(exitCode, readyAt, 180_000L, 123L, tail, safe)

    @Test fun preservesReportedProotExecErrorsInsteadOfCallingThemAndroidKills() {
        for (error in reported) {
            val failure = classify(listOf(
                error,
                "proot info: possible causes:",
                "  * the loader was not found or doesn't work.",
                "fatal error: see `libproot.so --help`.",
            ))
            assertEquals(error, FailureKind.LAUNCH_FAILED, failure.kind)
            assertEquals(error, failure.summary)
            assertNull(failure.upSeconds)
            assertEquals("launchFailed", failure.toMap()["kind"])
        }
    }

    @Test fun onlyAcceptsTheInitialProotCommandBeforeReadyOnAFailedProotRun() {
        for (error in reported) {
            assertEquals(FailureKind.KILLED, classify(listOf(error), readyAt = 0L).kind)
            assertEquals(FailureKind.KILLED, classify(listOf(error), exitCode = 0).kind)
            assertEquals(FailureKind.KILLED, classify(listOf("plugin says: $error")).kind)
            assertEquals(FailureKind.KILLED, classify(listOf(error.replace("/usr/bin/env", "/tmp/plugin-helper"))).kind)
        }
        for (line in listOf(
            "Permission denied",
            "Too many symbolic links encountered",
            "proot error: can't chmod '/tmp/proot-file': No such file or directory",
            "proot error: execve(\"/usr/bin/env\"): unexpected plugin output",
            "  * the loader was not found or doesn't work.",
        )) assertEquals(line, FailureKind.KILLED, classify(listOf(line)).kind)
    }

    @Test fun diskFullAndDshFatalKeepTheirPriority() {
        val fatal = "dsh: startup failed: required row missing"
        for (error in reported) {
            assertEquals(FailureKind.NO_SPACE, classify(listOf(error, "ENOSPC")).kind)
            val failure = classify(listOf(error, fatal))
            assertEquals(FailureKind.STARTUP_FAILED, failure.kind)
            assertEquals("startup failed: required row missing", failure.summary)
        }
    }


}
