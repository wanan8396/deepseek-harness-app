package app.dsh.runtime

import java.io.File
import java.io.IOException
import org.junit.Assert.*
import org.junit.Test

class GuestSetupTest {
    private fun mainFile(root: File, safe: Boolean) = File(root,
        if (safe) "var/lib/dsh-app/safe-mode/home/dsh-app/diagnostics.md"
        else "root/.dsh/dsh-app/diagnostics.md",
    )

    @Test fun defaultAndExplicitAutomaticCallsOnlyWriteTheMainSnapshot() {
        for (safe in listOf(false, true)) {
            val root = kotlin.io.path.createTempDirectory("diagnostics-default").toFile()
            try {
                val file = GuestSetup.writeDiagnostics(root, "# automatic first\n", safe)
                assertEquals(mainFile(root, safe).absoluteFile, file.absoluteFile)
                assertEquals("# automatic first\n", file.readText())
                GuestSetup.writeDiagnostics(root, "# automatic next\n", safe = safe)
                assertEquals("# automatic next\n", file.readText())
                assertEquals(listOf("diagnostics.md"), file.parentFile!!.list()!!.sorted())
            } finally { root.deleteRecursively() }
        }
    }

    @Test fun currentSnapshotLeavesAnExistingHistoricalManualCopyUntouched() {
        val root = kotlin.io.path.createTempDirectory("diagnostics-retained").toFile()
        try {
            val file = GuestSetup.writeDiagnostics(root, "# current\n")
            val historical = File(file.parentFile, "diagnostics-manual.md").apply { writeText("historical bytes") }
            GuestSetup.writeDiagnostics(root, "# next\n")
            assertEquals("# next\n", file.readText())
            assertEquals("historical bytes", historical.readText())
        } finally { root.deleteRecursively() }
    }

    @Test fun replacingTheSnapshotDoesNotTruncateAnAlreadyOpenReader() {
        for (safe in listOf(false, true)) {
            val root = kotlin.io.path.createTempDirectory("diagnostics-atomic").toFile()
            try {
                val manual = GuestSetup.writeDiagnostics(root, "# old capture\n", safe = safe)
                manual.inputStream().use { reader ->
                    GuestSetup.writeDiagnostics(root, "# new capture\n", safe = safe)
                    assertEquals("# old capture\n", reader.bufferedReader().readText())
                }
                assertEquals("# new capture\n", manual.readText())
                assertTrue(mainFile(root, safe).exists())
            } finally { root.deleteRecursively() }
        }
    }

    @Test fun normalAndSafeSnapshotsUseDistinctHomes() {
        val root = kotlin.io.path.createTempDirectory("diagnostics-homes").toFile()
        try {
            val normal = GuestSetup.writeDiagnostics(root, "# normal\n")
            val safe = GuestSetup.writeDiagnostics(root, "# safe\n", safe = true)
            GuestSetup.writeDiagnostics(root, "# next safe\n", safe = true)
            assertEquals("# normal\n", normal.readText())
            assertEquals("# next safe\n", safe.readText())
        } finally { root.deleteRecursively() }
    }

    @Test fun failedSnapshotReplacementDoesNotTouchHistoricalReports() {
        val root = kotlin.io.path.createTempDirectory("diagnostics-failure").toFile()
        try {
            val file = GuestSetup.writeDiagnostics(root, "# retained\n")
            val retained = file.readBytes()
            val blocked = File(file.parentFile, ".diagnostics.md.dsh-tmp").apply { mkdirs() }
            File(blocked, "block").writeText("keep")
            assertThrows(IOException::class.java) { GuestSetup.writeDiagnostics(root, "# partial\n") }
            assertArrayEquals(retained, file.readBytes())
        } finally { root.deleteRecursively() }
    }
}
