package app.dsh.runtime

import java.io.File
import org.junit.Assert.*
import org.junit.Test

class GuestAgentsModeTest {
    @Test fun officialPhoneInstructionsUseCurrentBrandAndAutomaticRootWithoutLegacyControls() {
        val root = kotlin.io.path.createTempDirectory("official-agents").toFile()
        try {
            for (rooted in listOf(false, true)) {
                GuestSetup.writeAgentsMd(root, phoneStorage = false, rootEngine = rooted)
                val text = File(root, "root/.dsh/AGENTS.md").readText()
                assertTrue(text.contains("当前产品名是 DeepSeek harness"))
                assertTrue(text.contains("每次启动自动检测一次真实 Android Root"))
                assertTrue(text.contains("权限页没有 Root 开关"))
                assertFalse(text.contains("启动方式由用户在权限页决定"))
                assertFalse(text.contains("默认目标是 dsh-go 原生界面"))
                assertFalse(text.contains("改 App 自己的样子用 dsh-go-ui"))
                assertEquals(rooted, text.contains("真实 Root / chroot，不运行 PRoot"))
            }
        } finally { root.deleteRecursively() }
    }

    @Test fun aUserOwnedFileIsUnchangedAcrossBothLaunchModes() {
        val root = kotlin.io.path.createTempDirectory("agents-user").toFile()
        try {
            val file = File(root, "root/.dsh/AGENTS.md")
            file.parentFile.mkdirs()
            val original = "# My own workspace instructions\nKeep my paths and examples.\n".toByteArray()
            file.writeBytes(original)
            for (rooted in listOf(true, false)) {
                GuestSetup.writeAgentsMd(root, phoneStorage = true, rootEngine = rooted)
                assertArrayEquals(original, file.readBytes())
            }
        } finally { root.deleteRecursively() }
    }

    @Test fun phoneStorageSendsOutputsOnlyToTheCurrentFolderAcrossLaunchModes() {
        val root = kotlin.io.path.createTempDirectory("agents-storage").toFile()
        try {
            for (rooted in listOf(false, true)) {
                GuestSetup.writeAgentsMd(root, phoneStorage = true, rootEngine = rooted)
                val text = File(root, "root/.dsh/AGENTS.md").readText()
                // Fixed contract, independent of PhoneStorage.OUTPUT_SUBDIR.
                assertTrue(text.contains("给用户的产出文件放到 `/sdcard/Download/DeepSeek-harness/`。"))
                assertFalse(text.contains("/sdcard/Download/DSH-Go/"))
                assertFalse(text.contains("/sdcard/Download/DSH/"))
            }
        } finally { root.deleteRecursively() }
    }

    @Test fun managedHistoricalInstructionsAreUpdatedButUserTakeoverKeepsItsOwnPaths() {
        val root = kotlin.io.path.createTempDirectory("agents-storage-upgrade").toFile()
        try {
            val file = File(root, "root/.dsh/AGENTS.md")
            file.parentFile!!.mkdirs()
            val old = "<!-- dsh-app:managed — old -->\nWrite outputs to /sdcard/Download/DSH-Go/.\n"
            for (rooted in listOf(false, true)) {
                file.writeText(old)
                GuestSetup.writeAgentsMd(root, phoneStorage = true, rootEngine = rooted)
                assertTrue(file.readText().contains("给用户的产出文件放到 `/sdcard/Download/DeepSeek-harness/`。"))
                assertFalse(file.readText().contains("/sdcard/Download/DSH-Go/"))
            }
            val owned = "# My instructions\nKeep /sdcard/Download/DSH-Go/ and /sdcard/Download/DSH/.\n".toByteArray()
            file.writeBytes(owned)
            for (rooted in listOf(false, true)) {
                GuestSetup.writeAgentsMd(root, phoneStorage = true, rootEngine = rooted)
                assertArrayEquals(owned, file.readBytes())
            }
        } finally { root.deleteRecursively() }
    }

    @Test fun diagnosticsSectionNamesThePathForEachLaunchMode() {
        val root = kotlin.io.path.createTempDirectory("agents-diagnostics").toFile()
        try {
            val file = File(root, "root/.dsh/AGENTS.md")
            GuestSetup.writeAgentsMd(root, phoneStorage = false)
            val proot = file.readText()
            assertTrue(proot.contains("## 本机诊断"))
            assertTrue(proot.contains("`\$DSH_HOME/dsh-app/diagnostics.md`"))
        } finally { root.deleteRecursively() }
    }

    @Test fun diagnosticsSnapshotIsWrittenWhereTheEngineCanReadIt() {
        val root = kotlin.io.path.createTempDirectory("agents-write").toFile()
        try {
            val file = GuestSetup.writeDiagnostics(root, "# first\n")
            assertEquals(File(root, "root/.dsh/dsh-app/diagnostics.md").absoluteFile, file.absoluteFile)
            assertEquals("# first\n", file.readText())
            GuestSetup.writeDiagnostics(root, "# second\n")
            assertEquals("# second\n", file.readText())
            assertEquals(0, file.parentFile!!.listFiles()!!.count { it.name.startsWith(".diagnostics") })
        } finally { root.deleteRecursively() }
    }

    @Test fun safeDiagnosticsLeaveOriginalHomeUntouchedAndNormalDiagnosticsReturnToIt() {
        val root = kotlin.io.path.createTempDirectory("diagnostics-safe").toFile()
        try {
            val original = GuestSetup.writeDiagnostics(root, "# original\n")
            val originalBytes = original.readBytes()
            val safeFile = GuestSetup.writeDiagnostics(root, "# rescue\n", safe = true)
            assertEquals(
                File(root, "var/lib/dsh-app/safe-mode/home/dsh-app/diagnostics.md").absoluteFile,
                safeFile.absoluteFile,
            )
            assertEquals("# rescue\n", safeFile.readText())
            assertArrayEquals(originalBytes, original.readBytes())
            val normalFile = GuestSetup.writeDiagnostics(root, "# normal again\n")
            assertEquals(original.absoluteFile, normalFile.absoluteFile)
            assertEquals("# normal again\n", original.readText())
            assertEquals("# rescue\n", safeFile.readText())
        } finally { root.deleteRecursively() }
    }

    @Test fun safeDiagnosticsDoNotNeedTheOriginalHomeToBeADirectory() {
        val root = kotlin.io.path.createTempDirectory("diagnostics-broken-home").toFile()
        try {
            val originalHome = File(root, "root/.dsh")
            originalHome.parentFile.mkdirs()
            val originalBytes = "original path is not a directory\n".toByteArray()
            originalHome.writeBytes(originalBytes)
            val safeFile = GuestSetup.writeDiagnostics(root, "# rescue\n", safe = true)
            assertEquals("# rescue\n", safeFile.readText())
            assertArrayEquals(originalBytes, originalHome.readBytes())
            assertEquals(0, safeFile.parentFile!!.listFiles()!!.count { it.name.startsWith(".diagnostics") })
        } finally { root.deleteRecursively() }
    }

    @Test fun phoneAndRecoveryAgentsNameTheSharedPrivateDependencyRoot() {
        val root = kotlin.io.path.createTempDirectory("agents-dependencies").toFile()
        try {
            val expected = "/root/.local/share/deepseek-harness/dependencies"
            val normal = File(root, "root/.dsh/AGENTS.md")
            for (rooted in listOf(false, true)) {
                GuestSetup.writeAgentsMd(root, phoneStorage = false, rootEngine = rooted)
                val text = normal.readText()
                assertTrue(text.contains(expected))
                assertTrue(text.contains("NPM_CONFIG_CACHE"))
                assertTrue(text.contains("PIP_CACHE_DIR"))
            }
            val owned = "# My own dependency choices\nKeep this file as-is.\n".toByteArray()
            normal.writeBytes(owned)
            GuestSetup.writeAgentsMd(root, phoneStorage = false, rootEngine = true)
            assertArrayEquals(owned, normal.readBytes())
            OfficialRuntime.prepareSafe(root)
            val safe = File(root, "var/lib/dsh-app/safe-mode/agents/AGENTS.md").readText()
            assertTrue(safe.contains(expected))
            assertTrue(safe.contains("PYTHONUSERBASE"))
            assertTrue(safe.contains("CARGO_HOME"))
            assertArrayEquals(owned, normal.readBytes())
        } finally { root.deleteRecursively() }
    }

    @Test fun unchangedDefaultStartupDoesNotRewriteAnExistingManagedFile() {
        val root = kotlin.io.path.createTempDirectory("agents-unchanged").toFile()
        try {
            val file = File(root, "root/.dsh/AGENTS.md")
            GuestSetup.writeAgentsMd(root, phoneStorage = true)
            val original = file.readBytes()
            assertTrue(file.setLastModified(1_234_567_000L))
            val modified = file.lastModified()
            GuestSetup.writeAgentsMd(root, phoneStorage = true)
            assertArrayEquals(original, file.readBytes())
            assertEquals(modified, file.lastModified())
        } finally { root.deleteRecursively() }
    }
}
