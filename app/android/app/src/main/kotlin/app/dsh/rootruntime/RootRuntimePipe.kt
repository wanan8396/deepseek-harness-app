package app.dsh.rootruntime

import app.dsh.wire.Frames
import app.dsh.wire.shellHelperEnvironment
import org.json.JSONObject
import java.io.Closeable
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.io.PipedInputStream
import java.io.PipedOutputStream
import java.util.Base64
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong
import kotlin.concurrent.thread

/** Long-lived engine transport. Only fixed probe/launch/recovery messages and bounded output frames. */
internal class RootRuntimePipe private constructor(private val process: Process) : Closeable {
    private val outputLock = Any()
    private val ids = AtomicLong()
    private val pending = ConcurrentHashMap<Long, CompletableFuture<JSONObject>>()
    private val stdoutInput = PipedInputStream(64 * 1024)
    private val stderrInput = PipedInputStream(64 * 1024)
    private val stdoutOutput = PipedOutputStream(stdoutInput)
    private val stderrOutput = PipedOutputStream(stderrInput)
    private val ended = CountDownLatch(1)
    @Volatile private var closed = false
    @Volatile private var finalCode: Int? = null
    @Volatile var engineStarted = false
        private set
    @Volatile var cleanupError: String? = null
        private set

    init {
        // su-manager diagnostics are not engine stderr and must not enter runtime logs.
        thread(isDaemon = true, name = "dsh-root-su-diagnostics") {
            runCatching { val bytes = ByteArray(4096); while (process.errorStream.read(bytes) >= 0) { } }
        }
        val reader = thread(isDaemon = true, name = "dsh-root-engine-frames") {
            try {
                if (!Frames.syncToMagic(process.inputStream)) throw IOException("root_denied")
                while (true) {
                    val bytes = Frames.read(process.inputStream) ?: break
                    val message = RootRuntimeProtocol.json(bytes)
                    when (message.optString("event")) {
                        "stdout", "stderr" -> {
                            val data = Base64.getDecoder().decode(message.getString("data"))
                            check(data.size <= 64 * 1024)
                            (if (message.getString("event") == "stdout") stdoutOutput else stderrOutput).apply {
                                write(data)
                                flush() // Wake the token/log reader instead of its 1000 ms pipe polling wait.
                            }
                        }
                        "exit" -> {
                            finalCode = message.getInt("code")
                            if (!message.optBoolean("clean")) cleanupError = "root_cleanup_blocked"
                            close()
                        }
                        else -> pending.remove(message.getLong("id"))?.complete(message)
                    }
                }
            } catch (_: Exception) {
                close()
            } finally {
                pending.values.forEach { it.completeExceptionally(IOException("root_disconnected")) }; pending.clear()
                runCatching { stdoutOutput.close() }; runCatching { stderrOutput.close() }
            }
        }
        thread(isDaemon = true, name = "dsh-root-engine-wait") {
            val actual = runCatching { process.waitFor() }.getOrDefault(125)
            reader.join()
            if (finalCode == null) {
                finalCode = if (engineStarted) RootRuntimeProtocol.CLEANUP_EXIT else actual
                if (engineStarted) cleanupError = "root_cleanup_blocked"
            }
            ended.countDown()
        }
    }

    fun alive(): Boolean = !closed && process.isAlive
    fun exchange(request: JSONObject, timeoutMs: Long): JSONObject {
        if (!alive()) throw IOException("root_disconnected")
        val id = ids.incrementAndGet()
        val future = CompletableFuture<JSONObject>()
        pending[id] = future
        try {
            synchronized(outputLock) { Frames.write(process.outputStream, RootRuntimeProtocol.bytes(request.put("id", id))) }
            return future.get(timeoutMs.coerceAtLeast(1), TimeUnit.MILLISECONDS)
        } catch (_: java.util.concurrent.TimeoutException) { throw IOException("root_timeout") }
        catch (_: Exception) { throw IOException("root_disconnected") }
        finally { pending.remove(id) }
    }
    fun probe(prepare: Boolean, timeoutMs: Long) = exchange(JSONObject().put("op", "probe").put("prepare", prepare), timeoutMs)
    fun launch(plan: RootLaunchPlan, beforeStart: () -> Unit): Process {
        val reply = exchange(plan.json().put("op", "launch"), 30_000)
        if (!reply.optBoolean("ok")) throw IOException(reply.optString("error", "root_launch_failed"))
        beforeStart()
        val run = exchange(JSONObject().put("op", "run"), 5000)
        if (!run.optBoolean("ok")) throw IOException("root_launch_failed")
        engineStarted = true
        return EngineProcess(this)
    }
    fun recover(plan: RootLaunchPlan): JSONObject {
        val reply = exchange(plan.json().put("op", "recover"), 120_000)
        if (!reply.optBoolean("ok")) throw IOException("root_cleanup_blocked")
        return reply
    }

    /** EOF asks the supervisor to retire only its namespace and finish ownership repair. */
    override fun close() {
        if (closed) return
        closed = true
        runCatching { process.outputStream.close() }
    }

    private class EngineProcess(private val pipe: RootRuntimePipe) : Process() {
        override fun getInputStream(): InputStream = pipe.stdoutInput
        override fun getErrorStream(): InputStream = pipe.stderrInput
        override fun getOutputStream(): OutputStream = object : OutputStream() {
            override fun write(b: Int) { throw IOException("root_stdin_reserved") }
            override fun close() = pipe.close()
        }
        override fun waitFor(): Int { pipe.ended.await(); return pipe.finalCode ?: 125 }
        override fun waitFor(timeout: Long, unit: TimeUnit) = pipe.ended.await(timeout, unit)
        override fun exitValue(): Int {
            if (isAlive) throw IllegalThreadStateException()
            return pipe.finalCode ?: 125
        }
        override fun isAlive(): Boolean = pipe.ended.count != 0L
        override fun destroy() = pipe.close()
        override fun destroyForcibly(): Process { pipe.close(); return this }
    }

    companion object {
        fun start(classpath: String): RootRuntimePipe {
            val command = "CLASSPATH=${RootRuntimeProtocol.quote(classpath)} exec /system/bin/app_process /system/bin ${RootLaunchMain::class.java.name}"
            val child = try {
                ProcessBuilder("su", "-c", command).apply {
                    environment().clear(); environment().putAll(shellHelperEnvironment(classpath))
                }.start()
            } catch (_: Exception) { throw IOException("root_unavailable") }
            return RootRuntimePipe(child)
        }
    }
}
