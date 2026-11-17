package app.dsh.rootruntime

import android.content.Context
import android.os.Process
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.nio.file.LinkOption.NOFOLLOW_LINKS
import java.nio.file.attribute.PosixFilePermissions

/** Each local-engine generation probes real Root once; no persisted preference can skip it. */
internal class RootRuntimeAccess(
    val marker: File,
    private val classpath: () -> String,
    private val appUid: () -> Int,
    private val startPipe: (String) -> RootRuntimePipe = { RootRuntimePipe.start(it) },
) {
    private val guard = Any()
    private var generation = 0L
    private var runtimeGeneration: Int? = null
    private var preferred = true
    private var launchPrepared = false
    private var launchCandidate: Candidate? = null
    private var state = "off"
    private var mode = "stopped"
    private var error: String? = null
    private var verified = false
    private var session: RootRuntimePipe? = null
    private var pending: RootRuntimePipe? = null

    private fun choose(value: Boolean) { preferred = value }
    fun beginRuntime(gen: Int) = synchronized(guard) {
        if (runtimeGeneration == gen) return@synchronized
        runtimeGeneration = gen; mode = "pending"; generation++; choose(true)
        launchPrepared = false; launchCandidate = null
    }
    fun launched(gen: Int, root: Boolean) = synchronized(guard) { if (runtimeGeneration == gen) mode = if (root) "root" else "proot" }
    fun endRuntime(gen: Int) = synchronized(guard) { if (runtimeGeneration == gen) stopRuntime() }
    fun stopRuntime() = synchronized(guard) {
        runtimeGeneration = null; mode = "stopped"; generation++
        launchPrepared = false; launchCandidate = null
        pending?.close(); pending = null; session?.close(); session = null; verified = false; state = "disconnected"
        error = if (Files.exists(marker.toPath(), NOFOLLOW_LINKS)) "root_cleanup_pending" else null
    }

    fun recoverBeforeGuestWrites(rootfs: File) {
        if (Files.exists(marker.toPath(), NOFOLLOW_LINKS) && prepareLaunch(rootfs) == null) throw IOException("root_cleanup_blocked")
    }

    fun fallback(reason: String) = synchronized(guard) {
        pending?.close(); pending = null; session?.close(); session = null
        verified = false; state = "unavailable"; error = reason; choose(false)
    }

    /** Recovery and launch share one real UID-0 probe, including a failed attempt, per start. */
    fun prepareLaunch(rootfs: File): Candidate? {
        val ticket: Long
        synchronized(guard) {
            if (mode == "root" || mode == "proot") return null
            if (launchPrepared) {
                if (launchCandidate == null && Files.exists(marker.toPath(), NOFOLLOW_LINKS)) throw IOException("root_cleanup_blocked")
                return launchCandidate
            }
            launchPrepared = true
            ticket = generation
        }
        var child: RootRuntimePipe? = null
        try {
            child = synchronized(guard) { session?.takeIf { it.alive() } } ?: startPipe(classpath()).also { next ->
                synchronized(guard) { if (generation != ticket) { next.close(); throw IOException("root_cancelled") }; pending = next }
            }
            val response = child.probe(true, RootRuntimeProtocol.REQUEST_MS)
            if (!RootRuntimeProtocol.accepted(response)) throw IOException(response.optString("error", "root_denied"))
            val bootId = RootBootIdentity.valid(response.getString("bootId"))
            if (Files.exists(marker.toPath(), NOFOLLOW_LINKS)) {
                child.recover(RootLaunchPlan(rootfs.canonicalPath, appUid(), appUid(), marker.absolutePath,
                    listOf("/usr/bin/env", "-i", "/bin/true"), "/"))
            }
            synchronized(guard) {
                if (ticket != generation) throw IOException("root_cancelled")
                pending = null; session = child; verified = true; state = "ready"; error = null; choose(true)
                return Candidate(this, child, ticket, rootfs, bootId).also { launchCandidate = it }
            }
        } catch (failure: Exception) {
            child?.close()
            synchronized(guard) {
                if (ticket == generation) { pending = null; session = null; verified = false; state = "unavailable"; error = stable(failure); choose(false) }
            }
            if (Files.exists(marker.toPath(), NOFOLLOW_LINKS)) throw IOException("root_cleanup_blocked")
            return null
        }
    }

    class Candidate internal constructor(private val owner: RootRuntimeAccess, private val pipe: RootRuntimePipe,
        private val ticket: Long, private val rootfs: File, private val bootId: String) {
        fun cancel(reason: String) {
            synchronized(owner.guard) {
                if (owner.generation == ticket && owner.session === pipe) {
                    pipe.close(); owner.session = null; owner.verified = false; owner.state = "unavailable"; owner.error = reason; owner.choose(false)
                }
            }
        }
        fun launch(argv: List<String>, beforeStart: () -> Unit): java.lang.Process? {
            val plan = RootLaunchPlan.fromProot(rootfs, owner.appUid(), owner.appUid(), owner.marker, argv)
            synchronized(owner.guard) {
                if (owner.generation != ticket || owner.session !== pipe) return null
                owner.markPending(plan, bootId)
            }
            return try { pipe.launch(plan, beforeStart) }
            catch (failure: Exception) {
                pipe.close()
                synchronized(owner.guard) { if (owner.session === pipe) { owner.session = null; owner.verified = false; owner.state = "unavailable"; owner.error = stable(failure); owner.choose(false) } }
                if (Files.exists(owner.marker.toPath(), NOFOLLOW_LINKS)) throw IOException("root_cleanup_blocked")
                null
            }
        }
    }

    private fun markPending(plan: RootLaunchPlan, bootId: String) {
        check(!Files.isSymbolicLink(marker.parentFile.toPath()) && !Files.isSymbolicLink(marker.toPath()))
        if (!marker.parentFile.isDirectory) check(marker.parentFile.mkdirs())
        val temporary = Files.createTempFile(marker.parentFile.toPath(), ".root-intent-", ".tmp",
            PosixFilePermissions.asFileAttribute(PosixFilePermissions.fromString("rw-------")))
        try {
            val value = JSONObject().put("v", 1).put("rootfs", plan.rootfs).put("appUid", plan.appUid).put("appGid", plan.appGid)
                .put("bootId", bootId)
            java.io.FileOutputStream(temporary.toFile()).use { it.write(value.toString().toByteArray()); it.fd.sync() }
            Files.move(temporary, marker.toPath(), java.nio.file.StandardCopyOption.ATOMIC_MOVE, java.nio.file.StandardCopyOption.REPLACE_EXISTING)
        } finally { Files.deleteIfExists(temporary) }
    }
    companion object {
        @Volatile private var instance: RootRuntimeAccess? = null
        fun get(context: Context): RootRuntimeAccess = instance ?: synchronized(this) {
            instance ?: context.applicationContext.let { app ->
                RootRuntimeAccess(File(app.filesDir, "runtime/root-cleanup-pending.json"),
                    { (listOf(app.applicationInfo.sourceDir) + app.applicationInfo.splitSourceDirs.orEmpty()).joinToString(":") },
                    { Process.myUid() }).also { instance = it }
            }
        }
        fun peek(): RootRuntimeAccess? = instance
        private fun stable(error: Exception): String = error.message?.takeIf { it.matches(Regex("root_[a-z_]+")) } ?: "root_unavailable"
    }
}
