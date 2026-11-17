package app.dsh.runtime

import java.io.File
import org.junit.Assert.*
import org.junit.Test

class LiteAppLifecycleTest {
    @Test fun onlyFinishingDestructionStopsTheRuntime() {
        for (finishing in listOf(false, true)) for (changing in listOf(false, true)) {
            assertEquals(finishing && !changing, LaunchStart.shouldStopOnDestroy(finishing, changing))
        }
    }

    @Test fun localLiteStartsOnEachIdleEntryButNotDuringAnotherTransition() {
        assertTrue(LaunchStart.shouldStartLite(false, "installed"))
        assertTrue(LaunchStart.shouldStartLite(false, "error"))
        for (phase in listOf(null, "notInstalled", "installing", "starting", "running", "stopping")) {
            assertFalse(LaunchStart.shouldStartLite(false, phase))
        }
        // There is deliberately no old auto_start_local preference in this decision.
        for (phase in RuntimeController.Phase.entries) {
            assertFalse(LaunchStart.shouldStartLite(true, phase.wire))
        }
    }

    @Test fun computerModeReadsOnlyTheNonSecretModeField() {
        assertTrue(LaunchStart.isComputerConnection("""{"mode":"computer","selectedId":"test"}"""))
        assertFalse(LaunchStart.isComputerConnection("""{"mode":"local"}"""))
        assertFalse(LaunchStart.isComputerConnection("""{"records":[{"mode":"computer"}]}"""))
        assertFalse(LaunchStart.isComputerConnection(null))
        assertFalse(LaunchStart.isComputerConnection("invalid"))
        assertFalse(LaunchStart.isComputerConnection("[]"))
    }

    @Test fun exitAndComputerModePreventLateStarts() {
        assertTrue(LaunchStart.shouldAllowLocalRuntime(true, false))
        assertFalse(LaunchStart.shouldAllowLocalRuntime(false, false))
        assertFalse(LaunchStart.shouldAllowLocalRuntime(true, true))
        assertFalse(LaunchStart.shouldAllowLocalRuntime(false, true))
    }

    @Test fun productionCallbacksKeepPauseSeparateFromExitAndUseTheManagedStop() {
        val source = File("src/main/kotlin/app/dsh")
        val activity = File(source, "MainActivity.kt").readText()
        val pause = activity.substringAfter("override fun onPause()").substringBefore("override fun onDestroy()")
        assertFalse(pause.contains("stopForAppExit"))
        assertFalse(pause.contains("cancelLiteStart"))
        assertTrue(activity.contains("LaunchStart.shouldStopOnDestroy(isFinishing, isChangingConfigurations)"))
        assertFalse(activity.contains("moveTaskToBack"))
        assertTrue(activity.substringAfter("override fun popSystemNavigator()").substringBefore("companion object").contains("finish()"))

        val service = File(source, "runtime/DshService.kt").readText()
        val removed = service.substringAfter("override fun onTaskRemoved(").substringBefore("override fun onDestroy()")
        assertTrue(removed.contains("stopForAppExit(this)"))
        val stop = service.substringAfter("fun stopForAppExit(context: Context)").substringBefore("/** With")
        assertTrue(stop.contains("LaunchStart.cancelLiteStart()"))
        assertTrue(stop.contains("RuntimeController.get(context).stopProcess()"))
        assertTrue(stop.contains("context.stopService("))
        assertFalse(stop.contains("kill"))

        val launch = File(source, "runtime/LaunchStart.kt").readText()
        assertTrue(launch.contains("flutter.web_connection.v1"))
        assertTrue(launch.contains("if (generation != liteGeneration || !live()) return@post"))
        assertTrue(launch.contains("controller.addSink(sink)"))
        assertTrue(launch.contains("controller.removeSink(sink)"))
        val runtime = File(source, "runtime/RuntimeController.kt").readText()
        assertEquals(2, Regex("!LaunchStart\\.localRuntimeAllowed\\(app\\)").findAll(runtime).count())
    }
}
