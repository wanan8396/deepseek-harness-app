package app.dsh.runtime

import java.io.File
import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Assume.assumeNoException
import org.junit.Test

class OfficialRuntimeTest {
    @Test fun explicitDistributionAndBothBooleanCapabilitiesAreRequired() {
        assertTrue(OfficialRuntime.isUnmodified("official-unmodified", false, false))
        for (distribution in listOf(null, "", "0.2.2-rc.2", "official", "official-unmodified ", true)) {
            assertFalse("distribution=$distribution", OfficialRuntime.isUnmodified(distribution, false, false))
        }
        for (capability in listOf(null, true, "false", 0, emptyMap<String, Any>())) {
            assertFalse("legacyBridge=$capability", OfficialRuntime.isUnmodified("official-unmodified", capability, false))
            assertFalse("enginePatches=$capability", OfficialRuntime.isUnmodified("official-unmodified", false, capability))
        }
    }

    @Test fun rescueUsesOfficialFreshTemplateArgumentsWithoutAnAppPatch() {
        val command = "cd /root && exec /usr/local/bin/dsh web --host 127.0.0.1 --port {PORT} --no-open"
        assertEquals(
            "cd /root && exec /usr/local/bin/dsh --profile dsh-app-safe --from-default-profile web --host 127.0.0.1 --port {PORT} --no-open",
            OfficialRuntime.profileArg(command, safe = true),
        )
        assertNull(OfficialRuntime.profileArg(command, safe = false))
        assertEquals(
            "exec /usr/local/bin/dsh web --port {PORT}",
            OfficialRuntime.profileArg("exec /usr/local/bin/dsh {DSH_PROFILE_ARGS} --port {PORT}", safe = false),
        )
        assertEquals(
            "exec /usr/local/bin/dsh --profile dsh-app-safe --from-default-profile web --port {PORT}",
            OfficialRuntime.profileArg("exec /usr/local/bin/dsh {DSH_PROFILE_ARGS} --port {PORT}", safe = true),
        )
    }

    @Test fun rescueLeavesUnrecognizedOrAmbiguousCommandsForTheCallerToReject() {
        for (command in listOf("/usr/bin/env", "/usr/local/bin/dsh tui --no-open", "dsh web --no-open",
            "/usr/local/bin/dsh web --no-open; /usr/local/bin/dsh web --no-open")) {
            assertNull(command, OfficialRuntime.profileArg(command, safe = true))
        }
    }

    @Test fun preparingOfficialRescueDoesNotCopyLastGoodOrWriteLegacyOverlayAndTool() = withRoot { root ->
        val original = file(root, "/root/.dsh/profiles/web/cordis.patch.yml").apply {
            parentFile.mkdirs()
            writeText("user settings stay here")
        }
        val lkg = file(root, "/var/lib/dsh-app/safe-mode/lkg.json").apply {
            parentFile.mkdirs()
            writeText("old last-good record")
        }
        OfficialRuntime.prepareSafe(root)
        assertTrue(file(root, "/var/lib/dsh-app/safe-mode/home").isDirectory)
        assertTrue(file(root, "/var/lib/dsh-app/safe-mode/agents/AGENTS.md").isFile)
        assertEquals("user settings stay here", original.readText())
        assertEquals("old last-good record", lkg.readText())
        assertFalse(file(root, "/var/lib/dsh-app/safe-mode/overlay.patch.yml").exists())
        assertFalse(file(root, "/var/lib/dsh-app/safe-mode/bin/dsh-app-plugins").exists())
        // Profile creation/replacement belongs to the official CLI, not an App-side JSON copy.
        assertFalse(file(root, "/var/lib/dsh-app/safe-mode/home/profiles").exists())
        val before = root.walkTopDown().filter { it.isFile }.associate { it.relativeTo(root).path to it.readText() }
        OfficialRuntime.prepareSafe(root)
        val after = root.walkTopDown().filter { it.isFile }.associate { it.relativeTo(root).path to it.readText() }
        assertEquals(before, after)
    }

    @Test fun oldRecoveryArtifactsAreLeftUnmodifiedAndNeverSelectedAsAPatch() = withRoot { root ->
        val overlay = file(root, "/var/lib/dsh-app/safe-mode/overlay.patch.yml").apply {
            parentFile.mkdirs()
            writeText("old legacy overlay")
        }
        val tool = file(root, "/var/lib/dsh-app/safe-mode/bin/dsh-app-plugins").apply {
            parentFile.mkdirs()
            writeText("old legacy tool")
        }
        val profile = file(root, "/var/lib/dsh-app/safe-mode/home/profiles/dsh-app-safe/package.json").apply {
            parentFile.mkdirs()
            writeText("left for official CLI replacement")
        }
        OfficialRuntime.prepareSafe(root)
        assertEquals("old legacy overlay", overlay.readText())
        assertEquals("old legacy tool", tool.readText())
        assertEquals("left for official CLI replacement", profile.readText())
        val command = OfficialRuntime.profileArg("exec /usr/local/bin/dsh web --port 3080", safe = true)!!
        assertFalse(command.contains("--patch"))
        assertTrue(command.contains("--from-default-profile web"))
    }

    @Test fun linkedRescueParentDoesNotWriteOutsideTheRootfs() = withRoot { root ->
        val outside = Files.createTempDirectory("official-rescue-outside").toFile()
        try {
            val parent = file(root, "/var/lib/dsh-app").apply { mkdirs() }
            val link = File(parent, "safe-mode")
            try {
                Files.createSymbolicLink(link.toPath(), outside.toPath())
            } catch (error: Exception) {
                assumeNoException("host does not support symlink creation", error)
            }
            assertThrows(java.io.IOException::class.java) { OfficialRuntime.prepareSafe(root) }
            assertTrue(outside.listFiles()!!.isEmpty())
            Files.deleteIfExists(link.toPath())
        } finally {
            outside.deleteRecursively()
        }
    }

    private fun file(root: File, guestPath: String) = File(root, guestPath.removePrefix("/"))
    private fun withRoot(block: (File) -> Unit) {
        val root = Files.createTempDirectory("official-runtime-test").toFile()
        try { block(root) } finally { root.deleteRecursively() }
    }
}
