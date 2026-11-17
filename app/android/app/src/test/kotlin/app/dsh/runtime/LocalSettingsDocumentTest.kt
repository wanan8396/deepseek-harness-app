package app.dsh.runtime

import java.io.File
import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class LocalSettingsDocumentTest {
    @get:Rule val temp = TemporaryFolder()
    private val normal = LocalSettingsDocument.Location("/root/.dsh", "web")
    private val safe = LocalSettingsDocument.Location("/var/lib/dsh-app/safe-mode/home", "dsh-app-safe")
    private fun args(home: String, safe: Boolean = false) = listOf("proot", "/usr/bin/env", "-i", "DSH_HOME=$home",
        "{GUEST_ENV}", "/bin/sh", "-c", "echo $$ > /tmp/dsh-web.pid; exec /usr/local/bin/dsh " +
            (if (safe) "--profile dsh-app-safe --from-default-profile web" else "web") +
            " --host 127.0.0.1 --port {PORT} --no-open")
    private fun file(root: File = temp.root, location: LocalSettingsDocument.Location = normal, bytes: ByteArray = "[]\n".toByteArray()): File =
        File(root, location.guestPath.removePrefix("/")).apply { parentFile.mkdirs(); writeBytes(bytes) }
    private fun failure(code: String, action: () -> Unit) {
        try { action(); fail("Expected $code") } catch (e: LocalSettingsDocument.Failure) { assertEquals(code, e.code) }
    }

    @Test fun capturesNormalAndSafeFromTheEffectiveEnvironment() {
        assertEquals(normal, LocalSettingsDocument.location(args("/root/.dsh"), emptyMap()))
        assertEquals(safe, LocalSettingsDocument.location(args("/root/.dsh", true), mapOf("DSH_HOME" to safe.home)))
        assertNull(LocalSettingsDocument.location(args("/root/.dsh"), mapOf("DSH_HOME" to "/sdcard/private")))
        assertNull(LocalSettingsDocument.location(args("/root/.dsh", true), emptyMap()))
    }
    @Test fun assignmentsAfterTheAppEnvironmentStillTakePrecedence() {
        val argv = args("/different").toMutableList()
        argv.add(argv.indexOf("{GUEST_ENV}") + 1, "DSH_HOME=/root/.dsh")
        assertEquals(normal, LocalSettingsDocument.location(argv, mapOf("DSH_HOME" to "/other")))
    }
    @Test fun unknownProfilesOrShellChangesAreNotGuessed() {
        for (command in listOf("exec /usr/local/bin/dsh tui", "exec /usr/local/bin/dsh web --host 0.0.0.0 --port {PORT} --no-open",
            args(normal.home).last() + "; echo extra", args(normal.home).last().replace(" web ", " --profile other "))) {
            assertNull(LocalSettingsDocument.location(args(normal.home).dropLast(1) + command, emptyMap()))
        }
        assertNull(LocalSettingsDocument.location(args(normal.home).filterNot { it == "{GUEST_ENV}" }, emptyMap()))
    }
    @Test fun originRequiresTheSameLoopbackAuthorityAndNoCredentialQuery() {
        assertTrue(LocalSettingsDocument.sameOrigin("http://127.0.0.1:41234", "http://127.0.0.1:41234/"))
        for (url in listOf("http://localhost:41234/", "http://127.0.0.1:41235/", "https://127.0.0.1:41234/",
            "http://127.0.0.1:41234/?token=x", "http://user@127.0.0.1:41234/", "file:///root/.dsh")) {
            assertFalse(LocalSettingsDocument.sameOrigin("http://127.0.0.1:41234/", url))
        }
    }
    @Test fun returnsTheActualTextWithoutWritingOrCreatingAnyFile() {
        val f = file(bytes = "- id: test\n  config: 中文\n".toByteArray())
        assertTrue(f.setLastModified(1_500_000_000L))
        val before = f.readBytes(); val modified = f.lastModified()
        val doc = LocalSettingsDocument.read(temp.root, normal)
        assertEquals("- id: test\n  config: 中文\n", doc.text)
        assertEquals("/root/.dsh/profiles/web/cordis.patch.yml", doc.location.guestPath)
        assertArrayEquals(before, f.readBytes()); assertEquals(modified, f.lastModified())
    }
    @Test fun safeConfigurationIsDistinctFromNormalConfiguration() {
        file(bytes = "normal\n".toByteArray()); file(location = safe, bytes = "rescue\n".toByteArray())
        assertEquals("rescue\n", LocalSettingsDocument.read(temp.root, safe).text)
        assertEquals("normal\n", LocalSettingsDocument.read(temp.root, normal).text)
    }
    @Test fun missingFileDoesNotCreateProfileDirectories() {
        failure("config_document_missing") { LocalSettingsDocument.read(temp.root, normal) }
        assertFalse(File(temp.root, "root").exists())
    }
    @Test fun fileByteBudgetIsEnforcedIncludingTheExactBoundary() {
        val f = file(bytes = ByteArray(512 * 1024) { 65 })
        assertEquals(512 * 1024, LocalSettingsDocument.read(temp.root, normal).text.length)
        f.appendBytes(byteArrayOf(65))
        failure("config_document_too_large") { LocalSettingsDocument.read(temp.root, normal) }
    }
    @Test fun malformedUtf8IsNotSilentlyReplaced() {
        file(bytes = byteArrayOf(0xc3.toByte(), 0x28))
        failure("config_document_utf8") { LocalSettingsDocument.read(temp.root, normal) }
    }
    @Test fun unsupportedLocationIsNotAnArbitraryFileRead() {
        failure("config_document_unsupported") {
            LocalSettingsDocument.read(temp.root, LocalSettingsDocument.Location("/root/.dsh/../", "web"))
        }
    }
    @Test fun rejectsALinkedLeafEvenWhenItsTargetIsInsideTheRoot() {
        val f = file(); val target = File(temp.root, "target.txt").apply { writeText("linked") }
        f.delete(); Files.createSymbolicLink(f.toPath(), target.toPath())
        failure("config_document_path") { LocalSettingsDocument.read(temp.root, normal) }
    }
    @Test fun rejectsLinkedParentsPointingOutsideTheRoot() {
        val outside = temp.newFolder("outside"); val root = temp.newFolder("rootfs")
        Files.createSymbolicLink(File(root, "root").toPath(), outside.toPath())
        failure("config_document_path") { LocalSettingsDocument.read(root, normal) }
        assertEquals(emptyList<String>(), outside.list()!!.toList())
    }
}
