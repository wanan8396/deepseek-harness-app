package app.dsh.rootruntime

import android.os.Process
import android.system.Os
import app.dsh.wire.Frames
import org.json.JSONObject
import java.io.FileDescriptor
import java.io.FileOutputStream
import java.io.InputStream
import java.util.Base64
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread
import kotlin.system.exitProcess

/** Only the app's private su pipes. No network listener, guest CLI, or generic shell RPC. */
@androidx.annotation.Keep
object RootLaunchMain {
    @JvmStatic fun main(args: Array<String>) {
        val output = FileOutputStream(FileDescriptor.out)
        val outputLock = Any()
        fun send(value: JSONObject) = synchronized(outputLock) { Frames.write(output, RootRuntimeProtocol.bytes(value)) }
        var capability: Boolean? = null
        val guard = Any()
        var child: java.lang.Process? = null
        var worker: Thread? = null
        var closing = false
        output.write(Frames.MAGIC); output.flush()
        try {
            while (true) {
                val raw = Frames.read(System.`in`) ?: break
                val request = RootRuntimeProtocol.json(raw)
                val id = request.getLong("id")
                fun reply(ok: Boolean, error: String? = null) = send(JSONObject().put("id", id).put("ok", ok)
                    .put("uid", Process.myUid()).put("revision", RootRuntimeProtocol.REVISION).put("error", error ?: JSONObject.NULL)
                    .apply { if (ok && request.optString("op") == "probe")
                        put("bootId", RootBootIdentity.valid(java.io.File("/proc/sys/kernel/random/boot_id").readText())) })
                when (request.optString("op")) {
                    "probe" -> {
                        if (Process.myUid() != 0) { reply(false, "root_denied"); continue }
                        if (request.optBoolean("prepare") && capability == null) {
                            capability = runCatching {
                                val probe = RootTools.namespace("probe")
                                synchronized(guard) { child = probe; if (closing) probe.destroyForcibly() }
                                discard(probe.inputStream); discard(probe.errorStream)
                                try { probe.waitFor(10, TimeUnit.SECONDS) && probe.exitValue() == 0 }
                                finally { if (probe.isAlive) probe.destroyForcibly(); synchronized(guard) { child = null } }
                            }.getOrDefault(false)
                        }
                        reply(capability == true, if (capability == true) null else "root_namespace_unavailable")
                    }
                    "run" -> {
                        val owned = synchronized(guard) { child.takeIf { worker != null && !closing } }
                        if (owned == null) reply(false, "root_not_ready") else {
                            reply(true)
                            owned.outputStream.write(1); owned.outputStream.flush()
                        }
                    }
                    "recover" -> {
                        if (Process.myUid() != 0 || synchronized(guard) { worker != null }) { reply(false, "root_busy"); continue }
                        try {
                            val plan = RootLaunchPlan.parse(request)
                            RootOwnershipRepair.retireRecordedNamespace(plan)
                            RootOwnershipRepair.finish(plan)
                            reply(true)
                        } catch (_: Exception) { reply(false, "root_cleanup_blocked") }
                    }
                    "launch" -> {
                        if (Process.myUid() != 0 || capability != true || synchronized(guard) { worker != null }) { reply(false, "root_not_ready"); continue }
                        val plan = RootLaunchPlan.parse(request)
                        worker = thread(name = "dsh-root-runtime", isDaemon = false) {
                            var namespace: java.lang.Process? = null
                            var namespacePin: java.io.FileDescriptor? = null
                            var started = false
                            var code = 125
                            var failure: String? = null
                            val pumps = ArrayList<Thread>()
                            try {
                                val owned = RootTools.namespace("run")
                                namespace = owned
                                synchronized(guard) {
                                    child = owned
                                    if (closing) { owned.outputStream.close(); throw java.io.IOException("root_cancelled") }
                                }
                                // The namespace emits only one preparation frame before user code.
                                Frames.write(owned.outputStream, RootRuntimeProtocol.bytes(plan.json()))
                                val prepared = Frames.read(owned.inputStream)?.let(RootRuntimeProtocol::json) ?: error("root_namespace_unavailable")
                                check(prepared.optBoolean("ok") && prepared.optInt("uid", -1) == 0 && prepared.optInt("pid", -1) > 1)
                                namespacePin = RootOwnershipRepair.recordNamespace(plan, prepared)
                                send(JSONObject().put("id", id).put("ok", true).put("uid", 0))
                                started = true
                                for ((name, stream) in listOf("stdout" to owned.inputStream, "stderr" to owned.errorStream)) {
                                    pumps += thread(isDaemon = true, name = "dsh-root-$name") {
                                        val buffer = ByteArray(16 * 1024)
                                        runCatching {
                                            while (true) {
                                                val n = stream.read(buffer); if (n < 0) break
                                                send(JSONObject().put("event", name).put("data", Base64.getEncoder().encodeToString(buffer.copyOf(n))))
                                            }
                                        }
                                    }
                                }
                                // The app updates its guest environment description before OP run releases PID 1.
                                code = owned.waitFor()
                            } catch (_: Exception) { failure = "root_launch_failed" }
                            finally {
                                namespace?.let { owned ->
                                    runCatching { owned.outputStream.close() }
                                    if (!runCatching { owned.waitFor(5, TimeUnit.SECONDS) }.getOrDefault(false)) {
                                        runCatching { owned.destroyForcibly() }
                                        runCatching { RootOwnershipRepair.retireRecordedNamespace(plan) }
                                    }
                                }
                                pumps.forEach { runCatching { it.join(2000) } }
                                val clean = runCatching {
                                    RootOwnershipRepair.retireRecordedNamespace(plan, namespacePin)
                                    RootOwnershipRepair.finish(plan)
                                }.isSuccess
                                namespacePin?.let { runCatching { Os.close(it) } }
                                if (!clean) failure = "root_cleanup_blocked"
                                synchronized(guard) { child = null }
                                runCatching {
                                    if (started) send(JSONObject().put("event", "exit").put("code", if (clean) code else RootRuntimeProtocol.CLEANUP_EXIT)
                                        .put("clean", clean).put("error", failure ?: JSONObject.NULL))
                                    else send(JSONObject().put("id", id).put("ok", false).put("clean", clean).put("error", failure ?: "root_launch_failed"))
                                }
                            }
                        }
                    }
                    else -> reply(false, "root_invalid_request")
                }
            }
        } catch (_: Exception) {
        } finally {
            synchronized(guard) {
                closing = true
                child?.let { runCatching { it.outputStream.close() } }
            }
            worker?.join()
        }
        exitProcess(0)
    }

    private fun discard(stream: InputStream) = thread(isDaemon = true) {
        runCatching { val bytes = ByteArray(4096); while (stream.read(bytes) >= 0) { } }
    }
}
