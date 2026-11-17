package app.dsh.runtime

import java.io.IOException
import org.junit.Assert.*
import org.junit.Test

class RuntimeProcessOwnershipTest {
    @Test fun capturedCleanupStateIsIsolatedByUidWithinTheSameRoot() {
        val root = "/test/cleanup-scope-${System.nanoTime()}"
        val owner = RuntimeProcessOwnership.cleanupState(root, 101)
        synchronized(owner) { owner.known[10] = "100" }
        val other = RuntimeProcessOwnership.cleanupState(root, 202)
        synchronized(other) { assertTrue(other.known.isEmpty()) }
        synchronized(owner) { assertEquals(mapOf(10 to "100"), owner.known) }
    }

    private class Reader : RuntimeProcessReader {
        val rows = mutableMapOf(10 to 101, 20 to 101)
        val denied = mutableSetOf<String>()
        val reads = mutableListOf<String>()
        var listed: List<Int> = listOf(10, 20)
        var exitOnStat = false
        var state = "S"
        var started = "100"
        private fun read(pid: Int, field: String) {
            reads += "$pid/$field"
            if ("$pid/$field" in denied) throw IOException("controlled observation failure")
        }
        override fun pids(): List<Int> {
            if ("list" in denied) throw IOException("cannot enumerate")
            return listed
        }
        override fun uid(pid: Int): Int? { read(pid, "uid"); return rows[pid] }
        override fun stat(pid: Int): String {
            if (exitOnStat) rows.remove(pid)
            read(pid, "stat")
            val fields = MutableList(20) { "0" }.also { it[0] = state; it[1] = "1"; it[19] = started }
            return "$pid (owned helper) " + fields.joinToString(" ")
        }
        override fun command(pid: Int): String { read(pid, "command"); return "sleep\u000030\u0000" }
        override fun cwd(pid: Int): String { read(pid, "cwd"); return "/owned/root" }
    }

    @Test fun unreadableUidIsUnknownAndCannotMeanSuccessfulCleanup() {
        val reader = Reader().apply { denied += "10/uid" }
        val snapshot = RuntimeProcessOwnership.scan(reader, 101, 20)
        assertFalse(snapshot.observed)
        assertEquals(setOf(10), snapshot.uncertain)
        assertTrue(snapshot.retired.isEmpty())
        assertTrue(snapshot.records.isEmpty())
    }

    @Test fun enumerationFailureStillInspectsCapturedIdentitiesButIsNotComplete() {
        val reader = Reader().apply { denied += "list" }
        val snapshot = RuntimeProcessOwnership.scan(reader, 101, 20, setOf(10))
        assertTrue(snapshot.enumerationFailed)
        assertFalse(snapshot.observed)
        assertEquals(listOf(10), snapshot.records.map { it.pid })
    }

    @Test fun failedEnumerationWithoutCapturedPidsCannotProveAnEmptyRuntime() {
        val reader = Reader().apply { denied += "list" }
        val unknown = RuntimeProcessOwnership.scan(reader, 101, 20)
        assertTrue(unknown.enumerationFailed)
        assertFalse(unknown.observed)
        assertTrue(unknown.uncertain.isEmpty())
        assertTrue(RuntimeProcessOwnership.owned(unknown.records, setOf("/owned/root"), 20).isEmpty())
        assertTrue(reader.reads.isEmpty())

        // The absent record was an observation gap, not a confirmed exit.
        reader.denied.clear()
        val recovered = RuntimeProcessOwnership.scan(reader, 101, 20)
        assertTrue(recovered.observed)
        assertEquals(listOf(10), RuntimeProcessOwnership.owned(recovered.records, setOf("/owned/root"), 20).map { it.pid })
    }

    @Test fun confirmedCapturedExitDoesNotRepairFailedGlobalEnumeration() {
        val reader = Reader().apply { denied += "list"; rows.remove(10) }
        val incomplete = RuntimeProcessOwnership.scan(reader, 101, 20, setOf(10))
        assertEquals(setOf(10), incomplete.retired)
        assertTrue(incomplete.records.isEmpty())
        assertFalse(incomplete.observed)

        reader.denied.clear()
        reader.listed = listOf(20)
        val complete = RuntimeProcessOwnership.scan(reader, 101, 20, setOf(10))
        assertTrue(complete.observed)
        assertEquals(setOf(10), complete.retired)
        assertTrue(complete.records.isEmpty())
    }

    @Test fun aKnownPidOmittedFromEnumerationIsExplicitlyRead() {
        val reader = Reader().apply { listed = emptyList() }
        val alive = RuntimeProcessOwnership.scan(reader, 101, 20, setOf(10))
        assertEquals(listOf(10), alive.records.map { it.pid })
        assertTrue(alive.observed)
        reader.rows.remove(10)
        val gone = RuntimeProcessOwnership.scan(reader, 101, 20, setOf(10))
        assertEquals(setOf(10), gone.retired)
        assertTrue(gone.observed)
    }

    @Test fun missingStatMustNotRetireAStillExistingPid() {
        val reader = Reader().apply { denied += "10/stat" }
        val unknown = RuntimeProcessOwnership.scan(reader, 101, 20)
        assertEquals(setOf(10), unknown.uncertain)
        assertTrue(unknown.retired.isEmpty())
        reader.exitOnStat = true
        val gone = RuntimeProcessOwnership.scan(reader, 101, 20)
        assertEquals(setOf(10), gone.retired)
        assertTrue(gone.observed)
    }

    @Test fun partialOwnershipReadsStayVisibleButBlockCompletion() {
        for (field in listOf("command", "cwd")) {
            val reader = Reader().apply { denied += "10/$field" }
            val snapshot = RuntimeProcessOwnership.scan(reader, 101, 20)
            assertFalse(snapshot.observed)
            assertEquals(setOf(10), snapshot.uncertain)
            val visible = RuntimeProcessOwnership.owned(snapshot.records, setOf("/owned/root"), 20).map { it.pid }
            assertEquals(if (field == "command") listOf(10) else emptyList<Int>(), visible)
            assertEquals(listOf(10), RuntimeProcessOwnership.owned(snapshot.records, setOf("/owned/root"), 20,
                mapOf(10 to "100")).map { it.pid })
        }
    }

    @Test fun confirmedOtherUidIsNeverReadAsAnOwnedProcess() {
        val reader = Reader().apply { rows[10] = 202 }
        val snapshot = RuntimeProcessOwnership.scan(reader, 101, 20, setOf(10))
        assertTrue(snapshot.observed)
        assertEquals(setOf(10), snapshot.retired)
        assertEquals(listOf("10/uid"), reader.reads)
    }

    @Test fun transientObservationFailureCanRecoverWithoutGuessingItExited() {
        val reader = Reader().apply { denied += "10/uid" }
        assertFalse(RuntimeProcessOwnership.scan(reader, 101, 20, setOf(10)).observed)
        reader.denied.clear()
        val recovered = RuntimeProcessOwnership.scan(reader, 101, 20, setOf(10))
        assertTrue(recovered.observed)
        assertEquals("100", recovered.records.single().started)
    }

    @Test fun zombiesAreRetiredAndReusedPidsDoNotMatchCapturedIdentity() {
        val reader = Reader().apply { state = "Z" }
        assertEquals(setOf(10), RuntimeProcessOwnership.scan(reader, 101, 20, setOf(10)).retired)
        reader.state = "S"
        reader.started = "200"
        val live = RuntimeProcessOwnership.scan(reader, 101, 20)
        val unrelated = live.records.map { it.copy(cwd = "/other/root") }
        assertTrue(RuntimeProcessOwnership.owned(unrelated, setOf("/owned/root"), 20, mapOf(10 to "100")).isEmpty())
    }

    @Test fun rootfsArgvAndCwdKeepSiblingRootsSeparateAndCaptureDescendants() {
        val root = "/owned/root"
        fun record(pid: Int, parent: Int = 1, argv: List<String> = listOf("sleep", "30"), cwd: String? = "/") =
            RuntimeProcessRecord(pid, parent, "start-$pid", argv, cwd)
        val rows = listOf(
            record(10, argv = listOf("proot", "-r", root)),
            record(11, parent = 10),
            record(12, parent = 11),
            record(20, cwd = "$root/work"),
            record(30, argv = listOf("proot", "--rootfs=$root")),
            record(40, argv = listOf("proot", "-b", "$root:/guest")),
            record(50, argv = listOf("proot", "-r", "$root-other")),
            record(60, cwd = "$root-other/work"),
            record(99, argv = listOf(root)),
        )
        assertEquals(listOf(10, 11, 12, 20, 30, 40), RuntimeProcessOwnership.owned(rows, setOf(root), 99).map { it.pid })
        assertEquals(listOf(50, 60), RuntimeProcessOwnership.owned(rows, setOf("$root-other"), 99).map { it.pid })
    }

    @Test fun capturedIdentityFindsDetachedChildrenWithoutAcceptingPidReuse() {
        val detached = RuntimeProcessRecord(10, 1, "100", listOf("sleep", "30"), "/")
        val child = RuntimeProcessRecord(11, 10, "110", listOf("sleep", "30"), "/")
        val reused = detached.copy(started = "200")
        assertEquals(listOf(10, 11), RuntimeProcessOwnership.owned(listOf(detached, child), setOf("/owned/root"), 99, mapOf(10 to "100")).map { it.pid })
        assertTrue(RuntimeProcessOwnership.owned(listOf(reused, child), setOf("/owned/root"), 99, mapOf(10 to "100")).isEmpty())
    }
}
