package app.dsh.runtime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class SessionDeletionTest {
    @get:Rule val temp = TemporaryFolder()

    @Test fun startupInventoryListsValidSessionIdsOnly() {
        val rootfs = temp.newFolder("rootfs")
        val project = File(SessionDeletion.sessionsRoot(rootfs), "project")
        val uuid = "842ba281-53D0-4b65-Be5e-268ed63bd333"
        val valid = listOf(uuid, "Ab".repeat(16), "cd".repeat(20), "EF".repeat(32))
            .flatMap { listOf(it, "session-$it") }
        val invalid = listOf("_mutations", "a".repeat(31), "a".repeat(33), "a".repeat(41), "a".repeat(65), "session-$uuid)")
        (valid + invalid).forEach { check(File(project, it).mkdirs()) }

        assertEquals(mapOf("project" to valid.sorted()), SessionDeletion.list(rootfs))
        valid.forEach { assertEquals("project", SessionDeletion.projectOf(rootfs, it)) }
        (invalid + "../project/$uuid").forEach { assertNull(SessionDeletion.projectOf(rootfs, it)) }
    }
}
