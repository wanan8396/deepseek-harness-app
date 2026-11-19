package app.dsh.rootruntime

import app.dsh.wire.Frames
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.io.IOException
import java.util.Base64
import java.util.concurrent.TimeUnit

class RootRuntimeTest {
    @Test fun automaticallyProbesOncePerStart() {
        withAccess { access, _, trace ->
            access.beginRuntime(1)
            assertFalse(trace.exists())
            val first = access.prepareLaunch(trace.parentFile)
            assertNotNull("Root must be tried without an opt-in preference", first)
            assertSame(first, access.prepareLaunch(trace.parentFile))
            access.beginRuntime(1)
            assertSame(first, access.prepareLaunch(trace.parentFile))
            assertEquals(listOf("probe"), trace.readLines())
            access.launched(1, true)
            assertNull(access.prepareLaunch(trace.parentFile))
            assertEquals(listOf("probe"), trace.readLines())
            access.endRuntime(1)
            access.beginRuntime(2)
            assertNotNull(access.prepareLaunch(trace.parentFile))
            assertEquals(listOf("probe", "probe"), trace.readLines())
        }
    }
    @Test fun failedProbeFallsBackForThisStartAndRetriesOnTheNext() {
        withAccess(listOf("denied", "running")) { access, _, trace ->
            access.beginRuntime(1)
            assertNull(access.prepareLaunch(trace.parentFile))
            assertNull(access.prepareLaunch(trace.parentFile))
            access.launched(1, false)
            assertNull(access.prepareLaunch(trace.parentFile))
            assertEquals(listOf("probe"), trace.readLines())
            access.endRuntime(1)
            access.beginRuntime(2)
            assertNotNull("A previous failure must not disable automatic Root", access.prepareLaunch(trace.parentFile))
            assertEquals(listOf("probe", "probe"), trace.readLines())
        }
    }
    @Test fun nonRootUidAndUnavailableSuUseProotWithoutClaimingAGrant() {
        withAccess(listOf("nonroot")) { access, _, trace ->
            access.beginRuntime(1)
            assertNull(access.prepareLaunch(trace.parentFile))
            assertEquals(listOf("probe"), trace.readLines())
        }
        val dir = java.nio.file.Files.createTempDirectory("root-no-su").toFile()
        var attempts = 0
        val access = RootRuntimeAccess(File(dir, "marker"), { "fixture" }, { 10123 }) {
            attempts++; throw IOException("root_unavailable")
        }
        try {
            access.beginRuntime(1)
            repeat(2) { assertNull(access.prepareLaunch(dir)) }
            assertEquals(1, attempts)
            access.launched(1, false)
            access.endRuntime(1); access.beginRuntime(2)
            assertNull(access.prepareLaunch(dir)); assertEquals(2, attempts)
        } finally { access.stopRuntime(); dir.deleteRecursively() }
    }
    @Test fun cleanupRecoveryAndLaunchReuseTheSameUidProbe() {
        withAccess { access, marker, trace ->
            marker.writeText("pending ownership repair")
            access.beginRuntime(1)
            val timings = linkedMapOf<String, Long>()
            access.recoverBeforeGuestWrites(trace.parentFile) { step, ms -> timings[step] = ms }
            assertTrue(timings.getValue("probe") >= 0L)
            assertEquals(23L, timings.getValue("namespace retirement"))
            assertEquals(523L, timings.getValue("ownership repair"))
            assertFalse(marker.exists())
            assertNotNull(access.prepareLaunch(trace.parentFile))
            assertEquals(listOf("probe", "recover"), trace.readLines())
        }
    }
    @Test fun failedCleanupRecoveryRetainsMarkerAndBlocksGuestWrites() {
        withAccess(listOf("denied")) { access, marker, trace ->
            marker.writeText("pending ownership repair")
            access.beginRuntime(1)
            repeat(2) {
                try { access.recoverBeforeGuestWrites(trace.parentFile); fail("must preserve pending cleanup") }
                catch (failure: IOException) { assertEquals("root_cleanup_blocked", failure.message) }
            }
            assertEquals("pending ownership repair", marker.readText())
            assertEquals(listOf("probe"), trace.readLines())
        }
    }
    @Test fun missingOrMalformedPrivilegedBootWitnessNeverEnablesLaunchOrClearsPendingCleanup() {
        for (mode in listOf("missingBoot", "invalidBoot")) {
            withAccess(listOf(mode)) { access, marker, trace ->
                marker.writeText("pending ownership repair")
                access.beginRuntime(1)
                try { access.recoverBeforeGuestWrites(trace.parentFile); fail("boot identity is required before recovery") }
                catch (failure: IOException) { assertEquals("root_cleanup_blocked", failure.message) }
                assertEquals("pending ownership repair", marker.readText())
                assertEquals(listOf("probe"), trace.readLines())
            }
            withAccess(listOf(mode)) { access, marker, trace ->
                access.beginRuntime(1)
                assertNull(access.prepareLaunch(trace.parentFile))
                assertFalse(marker.exists())
                assertEquals(listOf("probe"), trace.readLines())
            }
        }
    }
    private fun withAccess(modes: List<String> = listOf("running"), block: (RootRuntimeAccess, File, File) -> Unit) {
        val dir = java.nio.file.Files.createTempDirectory("root-auto-start").toFile()
        val marker = File(dir, "marker")
        val trace = File(dir, "trace")
        val children = mutableListOf<java.lang.Process>()
        val access = RootRuntimeAccess(marker, { "fixture" }, { 10123 }) {
            val (pipe, child) = fake(modes[children.size.coerceAtMost(modes.lastIndex)], trace, marker)
            children += child
            pipe
        }
        try { block(access, marker, trace) }
        finally {
            access.stopRuntime()
            children.forEach { assertTrue(it.waitFor(3, TimeUnit.SECONDS)) }
            dir.deleteRecursively()
        }
    }
    @Test fun extractsOnlyGuestArgvAndKeepsCommandQuoting() {
        val root = File("fixture-root")
        val command = "echo \$\$ > /tmp/dsh-web.pid; exec /usr/local/bin/dsh web --port 3080"
        val args = listOf("libproot.so", "-0", "-r", root.path, "-w", "/root/空 格", "/usr/bin/env", "-i", "HOME=/root",
            "PATH=/opt/node/bin:/usr/bin:/bin", "NODE_OPTIONS=--max-old-space-size=512", "/bin/sh", "-lc", command)
        val plan = RootLaunchPlan.fromProot(root, 10123, 10123, File("marker"), args)
        assertEquals("/usr/bin/env", plan.argv.first()); assertEquals("/root/空 格", plan.cwd)
        assertFalse(plan.argv.contains("libproot.so")); assertFalse(plan.argv.any { "proot-dns" in it })
        assertEquals(command, plan.argv.last())
        assertTrue(plan.argv.contains("PATH=/opt/node/bin:/usr/bin:/bin:/system/bin:/system/xbin:/vendor/bin"))
        assertTrue(plan.argv.contains("ANDROID_ROOT=/system"))
    }
    @Test fun explicitUserPathWinsWithoutImplicitExpansion() {
        val args = listOf("proot", "/usr/bin/env", "-i", "PATH=/usr/bin:/bin", "PATH=/chosen", "/bin/sh", "-c", "true")
        val plan = RootLaunchPlan.fromProot(File("root"), 10123, 10123, File("marker"), args)
        assertEquals(listOf("PATH=/usr/bin:/bin", "PATH=/chosen"), plan.argv.filter { it.startsWith("PATH=") })
    }
    @Test fun unknownLaunchOrInjectedLoaderIsRejected() {
        for (argv in listOf(listOf("proot", "sh"), listOf("proot", "/usr/bin/env", "-i", "LD_PRELOAD=guest.so", "/bin/sh"))) {
            try { RootLaunchPlan.fromProot(File("root"), 10123, 10123, File("marker"), argv); fail() } catch (_: IllegalArgumentException) { }
        }
    }
    @Test fun protocolProbeRequiresRealUidAndVersion() {
        fun probe(uid: Any, revision: String = RootRuntimeProtocol.REVISION) = JSONObject().put("uid", uid).put("revision", revision).put("ok", true)
        assertTrue(RootRuntimeProtocol.accepted(probe(0)))
        assertFalse(RootRuntimeProtocol.accepted(probe(2000))); assertFalse(RootRuntimeProtocol.accepted(probe("0")))
        assertFalse(RootRuntimeProtocol.accepted(probe(0, "old")))
    }
    @Test fun processAdapterDemultiplexesOutputAndKeepsActualExit() {
        val (pipe, child) = fake("exit")
        try {
            assertTrue(RootRuntimeProtocol.accepted(pipe.probe(true, 3000)))
            var prepared = false
            val engine = pipe.launch(plan()) { prepared = true }
            assertTrue(prepared)
            assertEquals("OUT\n", engine.inputStream.bufferedReader().readText())
            assertEquals("ERR\n", engine.errorStream.bufferedReader().readText())
            assertEquals(7, engine.waitFor()); assertFalse(engine.isAlive)
        } finally { pipe.close() }
        assertTrue(child.waitFor(3, TimeUnit.SECONDS))
    }
    @Test fun outputFramesWakeBlockedReadersWithoutWaitingForPipePolling() {
        val (pipe, child) = fake("stream")
        try {
            pipe.probe(true, 3000)
            val engine = pipe.launch(plan()) {}
            val out = java.util.concurrent.FutureTask { engine.inputStream.bufferedReader().readLine() }
            val err = java.util.concurrent.FutureTask { engine.errorStream.bufferedReader().readLine() }
            val readers = listOf(Thread(out, "root-test-stdout"), Thread(err, "root-test-stderr"))
            readers.forEach { it.isDaemon = true; it.start() }
            // Coordinate with the real PipedInputStream wait, not a sleep that may race its reader.
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(3)
            while (readers.any { it.state != Thread.State.TIMED_WAITING } && System.nanoTime() < deadline) Thread.yield()
            assertTrue("output readers must be waiting before the frame arrives",
                readers.all { it.state == Thread.State.TIMED_WAITING })
            pipe.exchange(JSONObject().put("op", "emit"), 3000)
            assertEquals("OUT", out.get(500, TimeUnit.MILLISECONDS))
            assertEquals("ERR", err.get(500, TimeUnit.MILLISECONDS))
        } finally {
            pipe.close()
            assertTrue(child.waitFor(3, TimeUnit.SECONDS))
        }
    }
    @Test fun engineStopUsesOwnedPipeAndWaitsForCleanupExit() {
        val (pipe, child) = fake("running")
        pipe.probe(true, 3000)
        val engine = pipe.launch(plan()) {}
        assertTrue(engine.isAlive)
        engine.destroy()
        assertTrue(engine.waitFor(3, TimeUnit.SECONDS)); assertEquals(143, engine.exitValue())
        assertTrue(child.waitFor(3, TimeUnit.SECONDS))
    }
    @Test fun pendingProbeTimeoutClosesWithoutLeavingChild() {
        val (pipe, child) = fake("pending")
        try { pipe.probe(true, 100); fail() } catch (e: IOException) { assertEquals("root_timeout", e.message) }
        pipe.close(); assertTrue(child.waitFor(3, TimeUnit.SECONDS))
    }
    private fun plan() = RootLaunchPlan("/fixture/rootfs", 10123, 10123, "/fixture/marker", listOf("/usr/bin/env", "-i", "/bin/true"), "/")
    private fun fake(mode: String, trace: File? = null, marker: File? = null): Pair<RootRuntimePipe, java.lang.Process> {
        val javaBin = File(System.getProperty("java.home"), if (System.getProperty("os.name", "").startsWith("Windows")) "bin/java.exe" else "bin/java")
        val cp = listOf(RootRuntimeFakeChild::class.java, Frames::class.java, JSONObject::class.java, kotlin.Unit::class.java)
            .map { File(requireNotNull(it.protectionDomain).codeSource.location.toURI()).path }.distinct().joinToString(File.pathSeparator)
        val child = ProcessBuilder(listOf(javaBin.path, "-cp", cp, RootRuntimeFakeChild::class.java.name, mode) +
            listOfNotNull(trace?.absolutePath, marker?.absolutePath)).start()
        val constructor = RootRuntimePipe::class.java.getDeclaredConstructor(java.lang.Process::class.java).apply { isAccessible = true }
        return constructor.newInstance(child) to child
    }
}

object RootRuntimeFakeChild {
    @JvmStatic fun main(args: Array<String>) {
        val mode = args[0]
        val trace = args.getOrNull(1)?.let(::File)
        val marker = args.getOrNull(2)?.let(::File)
        fun send(value: JSONObject) = Frames.write(System.out, value.toString().toByteArray())
        System.out.write(Frames.MAGIC); System.out.flush()
        var running = false
        while (true) {
            val bytes = Frames.read(System.`in`) ?: break
            val request = JSONObject(String(bytes))
            trace?.appendText(request.getString("op") + "\n")
            if (mode == "pending") continue
            if (request.getString("op") == "recover") marker?.delete()
            send(JSONObject().put("id", request.getLong("id")).put("ok", mode != "denied")
                .put("uid", if (mode == "nonroot") 2000 else 0).put("revision", "dsh.root-runtime.v1")
                .apply {
                    if (mode != "missingBoot") put("bootId", if (mode == "invalidBoot") "invalid" else "11111111-2222-4333-8444-555555555555")
                    if (mode == "denied") put("error", "root_denied")
                    if (request.getString("op") == "recover") { put("retireMs", 23L); put("repairMs", 523L) }
                })
            if (request.getString("op") == "emit") {
                send(JSONObject().put("event", "stdout").put("data", Base64.getEncoder().encodeToString("OUT\n".toByteArray())))
                send(JSONObject().put("event", "stderr").put("data", Base64.getEncoder().encodeToString("ERR\n".toByteArray())))
            }
            if (request.getString("op") == "run") {
                running = true
                if (mode == "exit") {
                    send(JSONObject().put("event", "stdout").put("data", Base64.getEncoder().encodeToString("OUT\n".toByteArray())))
                    send(JSONObject().put("event", "stderr").put("data", Base64.getEncoder().encodeToString("ERR\n".toByteArray())))
                    send(JSONObject().put("event", "exit").put("code", 7).put("clean", true)); return
                }
            }
        }
        if (running) send(JSONObject().put("event", "exit").put("code", 143).put("clean", true))
    }
}
