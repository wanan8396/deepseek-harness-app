package app.dsh.runtime

import java.io.File
import java.io.IOException
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Whether the next local start uses the rescue profile. */
enum class SafeState(val wire: String) {
    OFF("off"),

    /** Starts use the safe profile until the user asks for normal mode. */
    ON("on"),

    /** Back in normal mode on trial: a counted failure within the first two minutes returns to [ON]. */
    PROBATION("probation");

    companion object {
        fun parse(wire: String?): SafeState = entries.firstOrNull { it.wire == wire } ?: OFF
    }
}

/** The safe-mode state machine, free of Android so it can be checked on the JVM. */
object SafePolicy {
    const val STRIKE_LIMIT = 2
    const val HEALTHY_MS = 120_000L

    /**
     * Delay before restarting a run that was killed from outside after more than a minute up, or
     * null: at most three tries (5 s, 15 s, 45 s) in ten minutes. [recent] holds the earlier tries.
     */
    fun autoRestartDelay(kind: FailureKind, exitCode: Int, upMs: Long?, recent: List<Long>, now: Long): Long? {
        if (kind != FailureKind.KILLED || exitCode == 0 || upMs == null || upMs <= 60_000L) return null
        val count = recent.count { now - it < 600_000L }
        return listOf(5_000L, 15_000L, 45_000L).getOrNull(count)
    }

    /** [mode] is what the caller asked for: "safe", "normal", or null to keep the current mode. */
    fun onStartRequest(state: SafeState, mode: String?): SafeState = when (mode) {
        "safe" -> SafeState.ON
        "normal" -> if (state == SafeState.ON) SafeState.PROBATION else state
        else -> state
    }

    data class Outcome(
        val state: SafeState,
        val strikes: Int,
        /** Start again right away in safe mode. */
        val restartSafe: Boolean,
        val notice: String?,
        /** New value for the "why are we in safe mode" field; null keeps it. */
        val reason: String?,
    )

    fun onFailure(
        state: SafeState, strikes: Int, failure: RunFailure, autoSafe: Boolean,
        probationNotice: String = "正常模式还是起不来，已回到安全模式。", // l10n:keep test default
        autoNotice: String = "DSH 连续两次启动失败，已用安全模式启动。你的对话都在。", // l10n:keep test default
    ): Outcome {
        // Safe-mode runs never count against the main profile; uncounted kinds change nothing.
        if (failure.safeMode || !failure.kind.counts) return Outcome(state, strikes, false, null, null)
        val next = strikes + 1
        return when {
            state == SafeState.PROBATION ->
                Outcome(SafeState.ON, next, true, probationNotice, REASON_PROBATION)
            next >= STRIKE_LIMIT && autoSafe ->
                Outcome(SafeState.ON, next, true, autoNotice, REASON_AUTO)
            else -> Outcome(state, next, false, null, null)
        }
    }

    const val REASON_MANUAL = "manual"
    const val REASON_AUTO = "auto"
    const val REASON_PROBATION = "probation"
}

/** A file in the shared DSH home that also applies to the safe profile. */
data class Hazard(val path: String, val kind: String, val detail: String) {
    fun toMap(): Map<String, Any?> = mapOf("path" to path, "kind" to kind, "detail" to detail)
}

/**
 * Paths and preflight for the official rescue profile. No App patch or plugin repair tool is installed.
 */
object SafeMode {
    const val PROFILE = "dsh-app-safe"
    const val GUEST_DIR = "/var/lib/dsh-app/safe-mode"
    const val ORIGINAL_HOME = "/root/.dsh"
    const val HOME = "$GUEST_DIR/home"
    const val AGENTS_HOME = "$GUEST_DIR/agents"

    const val PROFILE_ARGS_PLACEHOLDER = "{DSH_PROFILE_ARGS}"

    /** Extra guest environment for safe starts only. */
    val GUEST_ENV: Map<String, String> = linkedMapOf(
        "DSH_HOME" to HOME, "DSH_APP_ORIGINAL_HOME" to ORIGINAL_HOME,
        "DSH_AGENTS_HOME" to AGENTS_HOME, "DSH_APP_SAFE_MODE" to "1",
    )

    // ── Preflight ───────────────────────────────────────────────────────────────────

    /** Files that move aside on request; nothing else is ever renamed. */
    val MOVABLE = listOf("/root/.dsh/cordis.patch.yml", "/root/.dsh/.env", "/root/.env")

    /** DSH 0.2.1's bootstrap-only names (`isBootstrapOnly` in dsh-app-boot): a `.env` setting one stops every profile. */
    private val BOOTSTRAP_NAMES = setOf(
        "PATH", "HOME", "USERPROFILE", "SHELL", "NODE_OPTIONS", "NODE_PATH", "NODE_EXTRA_CA_CERTS",
        "LD_PRELOAD", "LD_LIBRARY_PATH", "LD_AUDIT", "BASH_ENV", "ENV", "SHELLOPTS", "BASHOPTS",
        "PERL5OPT", "PERL5LIB", "PYTHONSTARTUP", "PYTHONPATH", "RUBYOPT", "RUBYLIB", "JAVA_TOOL_OPTIONS",
        "_JAVA_OPTIONS", "JDK_JAVA_OPTIONS", "PYTHONHOME", "GIT_SSH", "GIT_SSH_COMMAND", "GIT_EXTERNAL_DIFF",
        "GIT_PAGER", "GIT_EDITOR", "GIT_ASKPASS", "SSH_ASKPASS", "GIT_CONFIG_GLOBAL", "GIT_CONFIG_SYSTEM",
        "GIT_CONFIG_COUNT", "EDITOR", "VISUAL", "PAGER", "BROWSER", "DEEPSEEK_BASE_URL", "DEEPSEEK_SEARCH_BASE_URL",
        "SSL_CERT_FILE", "SSL_CERT_DIR", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY",
        "REQUESTS_CA_BUNDLE", "CURL_CA_BUNDLE", "NODE_TLS_REJECT_UNAUTHORIZED",
    )
    private val BOOTSTRAP_PREFIXES = listOf("DSH_", "XDG_", "DYLD_", "BASH_FUNC_")
    private val HOME_PROXY_NAMES = setOf("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY")
    private val ENV_NAME = Regex("^\\s*(?:export\\s+)?([A-Za-z_][A-Za-z0-9_.-]*)\\s*=")

    /** A patch layer that is only comments, blank lines or `[]`. */
    fun isTrivialPatch(text: String): Boolean {
        val body = text.lineSequence().map { it.trim() }.filter { it.isNotEmpty() && !it.startsWith("#") }.joinToString("")
        return body.isEmpty() || body == "[]"
    }

    /** Names in a `.env` that DSH refuses to start with ([home] = the `$DSH_HOME/.env`, which may set proxies). */
    fun launchOnlyNames(text: String, home: Boolean): List<String> = text.lineSequence()
        .mapNotNull { ENV_NAME.find(it)?.groupValues?.get(1) }
        .filter { name ->
            val upper = name.uppercase(Locale.ROOT)
            val bootstrap = upper in BOOTSTRAP_NAMES || BOOTSTRAP_PREFIXES.any { upper.startsWith(it) }
            bootstrap && !(home && upper in HOME_PROXY_NAMES)
        }
        .distinct()
        .toList()

    fun preflight(
        rootfs: File,
        patchDetail: String = "全局补丁文件：对所有配置（包括安全模式）都生效，可能就是它让 DSH 起不来。", // l10n:keep test default
        envDetail: (List<String>) -> String = { names ->
            "设置了 ${names.joinToString("、")}，DSH 不允许在 .env 里设置这些变量，会拒绝启动。" // l10n:keep test default
        },
    ): List<Hazard> {
        val out = ArrayList<Hazard>()
        readIfFile(guestFile(rootfs, MOVABLE[0]))?.let { text ->
            if (!isTrivialPatch(text)) {
                out += Hazard(MOVABLE[0], "homePatch", patchDetail)
            }
        }
        readIfFile(guestFile(rootfs, MOVABLE[1]))?.let { text ->
            val names = launchOnlyNames(text, home = true)
            if (names.isNotEmpty()) {
                out += Hazard(MOVABLE[1], "homeEnv", envDetail(names))
            }
        }
        readIfFile(guestFile(rootfs, MOVABLE[2]))?.let { text ->
            val names = launchOnlyNames(text, home = false)
            if (names.isNotEmpty()) {
                out += Hazard(MOVABLE[2], "cwdEnv", envDetail(names))
            }
        }
        return out
    }

    data class MoveAsideResult(val moved: List<Pair<String, String>>, val failure: IOException? = null)

    /** Stops at a failed rename; earlier successful moves remain available for the repair briefing. */
    fun moveAside(rootfs: File, guestPaths: List<String>, stamp: String): MoveAsideResult {
        val moved = ArrayList<Pair<String, String>>()
        for (path in guestPaths.distinct()) {
            if (path !in MOVABLE) continue
            val file = guestFile(rootfs, path)
            if (!file.isFile) continue
            var target = File(file.parentFile, "${file.name}.off-$stamp")
            var n = 1
            while (target.exists()) target = File(file.parentFile, "${file.name}.off-$stamp-${n++}")
            if (!file.renameTo(target)) {
                return MoveAsideResult(moved, IOException("could not move $path aside; ${moved.size} file(s) already moved"))
            }
            moved += path to (path.substringBeforeLast('/') + "/" + target.name)
        }
        return MoveAsideResult(moved)
    }

    /** `yyyyMMdd-HHmmss`, for `.off-` / `.bak-` suffixes. */
    fun stamp(at: Long = System.currentTimeMillis()): String =
        SimpleDateFormat("yyyyMMdd-HHmmss", Locale.ROOT).format(Date(at))

    // ── Small file helpers (plain java.io, so this file runs on the JVM too) ────────

    fun guestFile(rootfs: File, guestPath: String): File = File(rootfs, guestPath.removePrefix("/"))

    private fun readIfFile(file: File): String? = try {
        if (file.isFile) file.readText() else null
    } catch (_: Exception) {
        null
    }

}
