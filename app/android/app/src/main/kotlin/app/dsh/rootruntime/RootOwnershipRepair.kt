package app.dsh.rootruntime

import android.system.Os
import android.system.OsConstants
import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.nio.file.LinkOption.NOFOLLOW_LINKS
import java.nio.file.Path
import java.nio.file.FileVisitResult
import java.nio.file.SimpleFileVisitor
import java.nio.file.attribute.BasicFileAttributes

/** Runs only outside the retired mount/PID namespace. No recursive chown command or symlink walk. */
internal object RootOwnershipRepair {
    data class Inode(val device: Long, val inode: Long)
    internal fun linksContained(observed: Int, total: Long) = observed.toLong() == total

    fun repair(rootfs: File, uid: Int, gid: Int) {
        require(uid >= 10000 && gid >= 10000)
        val root = rootfs.toPath()
        if (!Files.isDirectory(root, NOFOLLOW_LINKS) || Files.isSymbolicLink(root)) throw IOException("root_cleanup_path")
        val device = Os.lstat(rootfs.absolutePath).st_dev
        val counts = HashMap<Inode, Int>()
        val totals = HashMap<Inode, Long>()
        fun inspect(path: Path) = Os.lstat(path.toString()).also {
            if (it.st_dev != device) throw IOException("root_cleanup_mount")
        }
        Files.walkFileTree(root, object : SimpleFileVisitor<Path>() {
            override fun preVisitDirectory(dir: Path, attrs: BasicFileAttributes): FileVisitResult { inspect(dir); return FileVisitResult.CONTINUE }
            override fun visitFile(file: Path, attrs: BasicFileAttributes): FileVisitResult {
                val stat = inspect(file)
                if (stat.st_uid != uid && stat.st_nlink > 1) {
                    val key = Inode(stat.st_dev, stat.st_ino)
                    counts[key] = (counts[key] ?: 0) + 1
                    val previous = totals.put(key, stat.st_nlink)
                    if (previous != null && previous != stat.st_nlink) throw IOException("root_cleanup_changed")
                }
                return FileVisitResult.CONTINUE
            }
        })
        for ((key, count) in counts) if (!linksContained(count, totals.getValue(key))) throw IOException("root_cleanup_hardlink")
        fun restore(path: Path) {
            val stat = inspect(path)
            if (stat.st_uid == uid) return
            if (!OsConstants.S_ISDIR(stat.st_mode) && stat.st_nlink > 1 &&
                !linksContained(counts[Inode(stat.st_dev, stat.st_ino)] ?: 0, stat.st_nlink)) throw IOException("root_cleanup_hardlink")
            Os.lchown(path.toString(), uid, gid)
            // chown clears set-id bits; preserve the user's original mode, never chmod 777.
            if (!OsConstants.S_ISLNK(stat.st_mode)) Os.chmod(path.toString(), stat.st_mode and 0xfff)
        }
        Files.walkFileTree(root, object : SimpleFileVisitor<Path>() {
            override fun preVisitDirectory(dir: Path, attrs: BasicFileAttributes): FileVisitResult { inspect(dir); return FileVisitResult.CONTINUE }
            override fun visitFile(file: Path, attrs: BasicFileAttributes): FileVisitResult { restore(file); return FileVisitResult.CONTINUE }
            override fun postVisitDirectory(dir: Path, error: IOException?): FileVisitResult {
                if (error != null) throw error
                restore(dir); return FileVisitResult.CONTINUE
            }
        })
    }

    private fun writeMarker(plan: RootLaunchPlan, value: org.json.JSONObject) {
        val marker = File(plan.marker).toPath()
        check(!Files.isSymbolicLink(marker))
        val temporary = Files.createTempFile(marker.parent, ".root-owner-", ".tmp")
        try {
            Os.chown(temporary.toString(), plan.appUid, plan.appGid); Os.chmod(temporary.toString(), 0x180)
            java.io.FileOutputStream(temporary.toFile()).use { out -> out.write(value.toString().toByteArray()); out.fd.sync() }
            Files.move(temporary, marker, java.nio.file.StandardCopyOption.ATOMIC_MOVE, java.nio.file.StandardCopyOption.REPLACE_EXISTING)
        } finally { Files.deleteIfExists(temporary) }
    }

    fun recordNamespace(plan: RootLaunchPlan, identity: org.json.JSONObject): java.io.FileDescriptor {
        val pid = identity.getInt("hostPid")
        val namespace = identity.getString("namespace")
        check(pid > 1 && namespace != Os.readlink("/proc/self/ns/mnt"))
        check(Os.stat("/proc/$pid").st_uid == 0 && Os.readlink("/proc/$pid/ns/mnt") == namespace)
        check(File("/proc/$pid/stat").readText().substringAfterLast(") ").split(' ')[19] == identity.getString("started"))
        val pin = Os.open("/proc/$pid/ns/mnt", OsConstants.O_RDONLY or OsConstants.O_CLOEXEC, 0)
        try {
            val value = org.json.JSONObject().put("v", 1).put("rootfs", plan.rootfs).put("appUid", plan.appUid).put("appGid", plan.appGid)
                .put("bootId", RootBootIdentity.valid(File("/proc/sys/kernel/random/boot_id").readText()))
                .put("hostPid", pid).put("started", identity.getString("started")).put("namespace", namespace)
            writeMarker(plan, value)
            return pin
        } catch (error: Exception) { Os.close(pin); throw error }
    }

    /** Namespace identity is unique and pinned by the supervisor. Never select by UID alone. */
    fun killNamespace(namespace: String, anchor: Int, keepAnchor: Boolean) {
        check(namespace.startsWith("mnt:[") && anchor > 1)
        fun members(): Map<Int, String> = buildMap {
            val directories = File("/proc").listFiles() ?: throw IOException("root_cleanup_observation")
            for (dir in directories) {
                val pid = dir.name.toIntOrNull() ?: continue
                if (pid == anchor) continue
                val ns = runCatching { Os.readlink("/proc/$pid/ns/mnt") }.getOrNull() ?: continue
                if (ns != namespace) continue
                // Only a member needs its identity read and parsed. The
                // signal path below still rechecks both start time and namespace.
                val stat = runCatching { File(dir, "stat").readText().substringAfterLast(") ").split(' ') }.getOrNull() ?: continue
                if (stat.getOrNull(0) == "Z" || stat.getOrNull(0) == "X") continue
                put(pid, stat.getOrNull(19) ?: throw IOException("root_cleanup_observation"))
            }
        }
        val deadline = System.nanoTime() + 5_000_000_000L
        while (true) {
            val owned = members()
            if (owned.isEmpty()) break
            for ((pid, born) in owned) runCatching {
                val now = File("/proc/$pid/stat").readText().substringAfterLast(") ").split(' ')
                if (now.getOrNull(19) == born && Os.readlink("/proc/$pid/ns/mnt") == namespace) Os.kill(pid, OsConstants.SIGKILL)
            }
            if (System.nanoTime() > deadline) throw IOException("root_cleanup_process")
            Thread.sleep(25)
        }
        if (!keepAnchor) runCatching {
            if (Os.readlink("/proc/$anchor/ns/mnt") == namespace) Os.kill(anchor, OsConstants.SIGKILL)
        }
    }

    fun markNamespaceRetired(plan: RootLaunchPlan) {
        val marker = File(plan.marker)
        if (!marker.isFile || Files.isSymbolicLink(marker.toPath())) return
        val value = org.json.JSONObject(marker.readText())
        check(value.getString("rootfs") == plan.rootfs)
        writeMarker(plan, value.put("namespaceRetired", true))
    }

    fun retireRecordedNamespace(plan: RootLaunchPlan, pinned: java.io.FileDescriptor? = null) {
        val marker = File(plan.marker)
        if (!marker.exists()) return
        check(!Files.isSymbolicLink(marker.toPath()) && marker.length() <= 16 * 1024)
        val value = org.json.JSONObject(marker.readText())
        check(value.getInt("v") == 1 && value.getString("rootfs") == plan.rootfs &&
            value.getInt("appUid") == plan.appUid && value.getInt("appGid") == plan.appGid)
        if (value.optBoolean("namespaceRetired") || !value.has("hostPid")) return
        val recordedBoot = if (value.has("bootId")) value.getString("bootId") else null
        val currentBoot = File("/proc/sys/kernel/random/boot_id").readText()
        val previousBoot = RootBootIdentity.previousBoot(recordedBoot, currentBoot, value.getString("started"),
            if (recordedBoot == null) File("/proc/uptime").readText().trim().substringBefore(' ') else "0",
            if (recordedBoot == null) Os.sysconf(OsConstants._SC_CLK_TCK) else 1)
        if (previousBoot) {
            // Reboot retired every old namespace. Its numeric inode/PID may now
            // belong to unrelated apps: never inspect or signal by that old name.
            markNamespaceRetired(plan)
            return
        }
        val pid = value.getInt("hostPid"); val namespace = value.getString("namespace")
        check(namespace != Os.readlink("/proc/self/ns/mnt"))
        val stillAnchor = runCatching {
            File("/proc/$pid/stat").readText().substringAfterLast(") ").split(' ')[19] == value.getString("started") &&
                Os.readlink("/proc/$pid/ns/mnt") == namespace
        }.getOrDefault(false)
        if (!stillAnchor && pinned == null) throw IOException("root_cleanup_namespace_unknown")
        val pin = pinned ?: Os.open("/proc/$pid/ns/mnt", OsConstants.O_RDONLY or OsConstants.O_CLOEXEC, 0)
        try {
            killNamespace(namespace, pid, keepAnchor = true)
            markNamespaceRetired(plan)
            if (stillAnchor) killNamespace(namespace, pid, keepAnchor = false)
        } finally { if (pinned == null) Os.close(pin) }
    }

    fun finish(plan: RootLaunchPlan) {
        repair(File(plan.rootfs), plan.appUid, plan.appGid)
        val marker = File(plan.marker)
        if (Files.isSymbolicLink(marker.toPath())) throw IOException("root_cleanup_marker")
        Files.deleteIfExists(marker.toPath())
    }
}
