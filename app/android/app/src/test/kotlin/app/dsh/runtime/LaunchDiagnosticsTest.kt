package app.dsh.runtime

import org.junit.Assert.*
import org.junit.Test

class LaunchDiagnosticsTest {
    @Test fun selectionIsNotRunningUntilSpawnedAndAlive() {
        val run = LaunchDiagnostics()
        run.selectedProot()
        assertNull(run.currentMode(true))
        run.failed("startFailed")
        assertEquals("proot", run.selectedMode)
        assertFalse(run.spawned)
        assertEquals("startFailed", run.failureReason)
    }
    @Test fun rootSelectionReportsOnlyTheRealSpawnedLifetime() {
        val run = LaunchDiagnostics()
        run.selectedRoot()
        assertNull(run.currentMode(true))
        run.spawned()
        assertEquals("root", run.currentMode(true))
        run.failed("exit:1")
        assertNull(run.currentMode(false))
        assertTrue(run.spawned)
    }
    @Test fun aNewAttemptNeverInheritsAnOldFailure() {
        val old = LaunchDiagnostics().apply { selectedRoot(); failed("startFailed") }
        val next = LaunchDiagnostics().apply { selectedProot(); spawned() }
        assertEquals("startFailed", old.failureReason)
        assertNull(next.failureReason)
        assertEquals("proot", next.currentMode(true))
    }
}
