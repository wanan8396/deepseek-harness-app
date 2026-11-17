package app.dsh.runtime

import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.StandardCopyOption

/** Explicit distribution contract; an engine version alone says nothing about local patches. */
object OfficialRuntime {
    fun isUnmodified(engineDistribution: Any?, legacyBridge: Any?, enginePatches: Any?): Boolean =
        engineDistribution == "official-unmodified" && legacyBridge == false && enginePatches == false

    // Official CLI rebuilds this custom profile from its shipped web template on every rescue start.
    // There is deliberately no app --patch layer, plugin helper or copied last-good configuration.
    const val SAFE_PROFILE_ARGS = "--profile ${SafeMode.PROFILE} --from-default-profile web"
    private const val WEB_COMMAND = "/usr/local/bin/dsh web "

    /** Same launch-template contract as SafeMode, using only official profile initialization. */
    fun profileArg(arg: String, safe: Boolean): String? {
        if (arg.contains(SafeMode.PROFILE_ARGS_PLACEHOLDER)) {
            return arg.replace(SafeMode.PROFILE_ARGS_PLACEHOLDER, if (safe) SAFE_PROFILE_ARGS else "web")
        }
        if (!safe) return null
        val first = arg.indexOf(WEB_COMMAND)
        if (first < 0 || arg.indexOf(WEB_COMMAND, first + 1) >= 0) return null
        return arg.replace(WEB_COMMAND, "/usr/local/bin/dsh $SAFE_PROFILE_ARGS ")
    }

    /** Reuses the isolated rescue data/diagnostics paths, without writing legacy recovery artifacts. */
    fun prepareSafe(rootfs: File) {
        ensureDirectory(rootfs, SafeMode.HOME)
        ensureDirectory(rootfs, SafeMode.AGENTS_HOME)
        // l10n:keep official runtime rescue briefing
        val briefing = """# 官方运行时恢复配置

当前界面是手机本机 DeepSeek Harness 网页。App 使用官方 web 模板重建 `${SafeMode.PROFILE}`，没有加入 App 的旧恢复补丁或修复工具；官方插件管理和其他默认功能保持原样。
当前 DSH_HOME 是 `${SafeMode.HOME}`；正常模式的数据仍在 `${SafeMode.ORIGINAL_HOME}`，没有复制对话、插件配置或凭据。恢复环境可能需要重新配置模型。
本机诊断位于 `${SafeMode.HOME}/dsh-app/diagnostics.md`，可先在 App 设置中生成。检查时间和版本；日志、密钥与私人文件内容不要原样贴到外部报告。
修复正常配置前先保留备份，不要删除原始对话或凭据。用户可从 App 恢复正常模式。
""" + "\n\n" + GuestDependencies.instructions()
        val target = File(rootfs, "${SafeMode.AGENTS_HOME.removePrefix("/")}/AGENTS.md").toPath()
        val temp = Files.createTempFile(target.parent, ".official-agents-", ".tmp")
        try {
            Files.write(temp, briefing.toByteArray(Charsets.UTF_8))
            Files.move(temp, target, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
        } finally {
            Files.deleteIfExists(temp)
        }
    }

    private fun ensureDirectory(rootfs: File, guestPath: String) {
        var current = rootfs.toPath()
        for (part in guestPath.removePrefix("/").split('/')) {
            current = current.resolve(part)
            if (Files.isSymbolicLink(current)) throw IOException("linked official rescue directory: $current")
            if (Files.exists(current, LinkOption.NOFOLLOW_LINKS)) {
                if (!Files.isDirectory(current, LinkOption.NOFOLLOW_LINKS)) throw IOException("invalid official rescue directory: $current")
            } else Files.createDirectory(current)
        }
    }
}
