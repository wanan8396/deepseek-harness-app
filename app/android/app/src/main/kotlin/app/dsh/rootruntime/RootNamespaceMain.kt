package app.dsh.rootruntime

import android.os.Process
import android.system.Os
import app.dsh.wire.Frames
import app.dsh.wire.shellHelperEnvironment
import org.json.JSONObject
import java.io.File
import java.io.FileDescriptor
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.LinkOption.NOFOLLOW_LINKS
import java.util.concurrent.TimeUnit
import kotlin.system.exitProcess

internal object RootTools {
    fun command(applet: String): List<String> = File("/system/bin/$applet").takeIf { it.canExecute() }
        ?.let { listOf(it.path) } ?: listOf("/system/bin/toybox", applet)
    fun run(argv: List<String>, timeout: Long = 5000): Boolean {
        val process = ProcessBuilder(argv).redirectOutput(File("/dev/null")).redirectError(File("/dev/null")).start()
        return try { process.waitFor(timeout, TimeUnit.MILLISECONDS) && process.exitValue() == 0 }
        finally { if (process.isAlive) process.destroyForcibly() }
    }
    /** Mount namespaces work on the target kernel; PID namespaces are deliberately not required. */
    fun namespace(mode: String): java.lang.Process = ProcessBuilder(command("unshare") + listOf("-m",
        "/system/bin/app_process", "/system/bin", RootNamespaceMain::class.java.name, mode, Os.readlink("/proc/self/ns/mnt"))).apply {
        environment().clear(); environment().putAll(shellHelperEnvironment(System.getenv("CLASSPATH") ?: ""))
    }.start()
}

/** A normal process in a unique private mount namespace; Android init reaps orphaned descendants. */
@androidx.annotation.Keep
object RootNamespaceMain {
    @JvmStatic fun main(args: Array<String>) {
        val output = FileOutputStream(FileDescriptor.out)
        var plan: RootLaunchPlan? = null
        var acknowledged = false
        var privateNamespace = false
        val exitLock = Any()
        fun finish(code: Int): Nothing {
            synchronized(exitLock) {
                if (privateNamespace) runCatching {
                    RootOwnershipRepair.killNamespace(Os.readlink("/proc/self/ns/mnt"), Process.myPid(), keepAnchor = true)
                    plan?.let(RootOwnershipRepair::markNamespaceRetired)
                }
                exitProcess(code)
            }
        }
        try {
            require(args.size == 2 && Process.myUid() == 0 && Process.myPid() > 1) { "root_namespace_identity" }
            require(Os.readlink("/proc/self/ns/mnt") != args[1]) { "root_namespace_identity" }
            privateNamespace = true
            check(RootTools.run(RootTools.command("mount") + listOf("-o", "rprivate", "none", "/"))) { "root_namespace_unavailable" }
            if (args[0] == "probe") {
                check(RootTools.run(RootTools.command("chroot") + listOf("/", "/system/bin/sh", "-c", "test \"\$(id -u)\" = 0")))
                // The fixed probe commands have both exited. No guest or owner thread
                // was started; exiting releases this probe-only namespace. Failure
                // and real launch paths still retire descendants through finish().
                exitProcess(0)
            }
            val parsed = RootLaunchPlan.parse(RootRuntimeProtocol.json(Frames.read(System.`in`) ?: return))
            plan = parsed
            val permit = java.util.concurrent.CountDownLatch(1)
            Thread({
                if (System.`in`.read() != 1) finish(125)
                permit.countDown()
                runCatching { while (System.`in`.read() >= 0) { } }
                finish(125)
            }, "dsh-root-namespace-owner").apply { isDaemon = true; start() }
            prepare(parsed)
            val probeArgv = RootTools.command("chroot") + listOf(parsed.rootfs, "/usr/bin/env", "-i", "PATH=/usr/bin:/bin:/opt/node/bin",
                "/bin/sh", "-c", "test \"\$(id -u)\" = 0 && /opt/node/bin/node -e 'process.exit(process.getuid() === 0 ? 0 : 1)'")
            check(RootTools.run(probeArgv, 10_000)) { "root_guest_probe" }
            val started = File("/proc/self/stat").readText().substringAfterLast(") ").split(' ')[19]
            Frames.write(output, RootRuntimeProtocol.bytes(JSONObject().put("ok", true).put("uid", 0).put("pid", Process.myPid())
                .put("hostPid", Process.myPid()).put("started", started).put("namespace", Os.readlink("/proc/self/ns/mnt"))))
            acknowledged = true
            permit.await()
            val child = ProcessBuilder(RootTools.command("chroot") + listOf(parsed.rootfs, "/bin/sh", "-c",
                "cd -- ${RootRuntimeProtocol.quote(parsed.cwd)} && exec \"\$@\"", "dsh-root") + parsed.argv).apply {
                environment().clear(); environment().putAll(shellHelperEnvironment(System.getenv("CLASSPATH") ?: ""))
                redirectOutput(ProcessBuilder.Redirect.INHERIT); redirectError(ProcessBuilder.Redirect.INHERIT)
                redirectInput(File("/dev/null"))
            }.start()
            finish(child.waitFor())
        } catch (_: Exception) {
            if (!acknowledged) runCatching { Frames.write(output, RootRuntimeProtocol.bytes(JSONObject().put("ok", false).put("error", "root_namespace_unavailable"))) }
            finish(125)
        }
    }

    private fun prepare(plan: RootLaunchPlan) {
        val root = File(plan.rootfs).toPath()
        check(Files.isDirectory(root, NOFOLLOW_LINKS) && !Files.isSymbolicLink(root))
        fun target(relative: String): String {
            var cursor = root
            for (part in relative.split('/')) {
                cursor = cursor.resolve(part)
                if (!Files.exists(cursor, NOFOLLOW_LINKS)) Files.createDirectory(cursor)
                check(Files.isDirectory(cursor, NOFOLLOW_LINKS) && !Files.isSymbolicLink(cursor))
            }
            return cursor.toString()
        }
        // /data is non-recursive because the rootfs is itself beneath /data.
        for ((host, recursive) in listOf("/system" to true, "/apex" to true, "/dev" to true, "/sys" to false,
            "/data" to false, "/storage" to true, "/sdcard" to true, "/linkerconfig" to true,
            "/vendor" to true, "/product" to true, "/system_ext" to true, "/odm" to true)) {
            if (!File(host).isDirectory) {
                check(host in setOf("/storage", "/sdcard", "/linkerconfig", "/vendor", "/product", "/system_ext", "/odm"))
                continue
            }
            check(RootTools.run(RootTools.command("mount") + listOf("-o", if (recursive) "rbind" else "bind", host, target(host.removePrefix("/")))))
        }
        check(RootTools.run(RootTools.command("mount") + listOf("-t", "proc", "proc", target("proc"))))
    }
}
