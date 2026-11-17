package app.dsh.runtime

import java.io.File
import java.io.IOException
import java.nio.channels.Channels
import java.nio.file.Files
import java.nio.file.LinkOption.NOFOLLOW_LINKS
import java.nio.file.NoSuchFileException
import java.nio.file.Path
import java.nio.file.StandardCopyOption.ATOMIC_MOVE
import java.nio.file.StandardCopyOption.REPLACE_EXISTING
import java.nio.file.StandardOpenOption.READ
import java.nio.file.StandardOpenOption.TRUNCATE_EXISTING
import java.nio.file.StandardOpenOption.WRITE
import java.nio.file.attribute.BasicFileAttributes

/** Guest-only tools and caches, outside the engine's fixed upgrade paths and DSH profiles. */
object GuestDependencies {
    const val ROOT = "/root/.local/share/deepseek-harness/dependencies"
    private const val README_MARKER = "<!-- deepseek-harness:managed-dependencies-v1 -->"
    private val directories = listOf(
        "bin", "npm/bin", "python/bin", "venvs", "downloads", "sources", "build", "tmp",
        "cache/npm", "cache/node-gyp", "cache/pip", "cache/go-mod", "cache/go-build", "cache/ccache",
        "cargo/bin", "rustup", "go/bin",
    )
    private val variables = linkedMapOf(
        "DSH_DEPENDENCY_ROOT" to ROOT,
        "NPM_CONFIG_PREFIX" to "$ROOT/npm",
        "NPM_CONFIG_CACHE" to "$ROOT/cache/npm",
        "NPM_CONFIG_DEVDIR" to "$ROOT/cache/node-gyp",
        "PYTHONUSERBASE" to "$ROOT/python",
        "PIP_CACHE_DIR" to "$ROOT/cache/pip",
        "CARGO_HOME" to "$ROOT/cargo",
        "RUSTUP_HOME" to "$ROOT/rustup",
        "GOPATH" to "$ROOT/go",
        "GOMODCACHE" to "$ROOT/cache/go-mod",
        "GOCACHE" to "$ROOT/cache/go-build",
        "CCACHE_DIR" to "$ROOT/cache/ccache",
        "TMPDIR" to "$ROOT/tmp",
    )
    private val bins = listOf("bin", "npm/bin", "python/bin", "cargo/bin", "go/bin").map { "$ROOT/$it" }

    /** Call before guest processes start, after recovering private-rootfs ownership. No migration. */
    fun prepare(rootfs: File): File {
        val rawRoot = rootfs.toPath().toAbsolutePath()
        val runtime = rawRoot.parent ?: throw IOException("dependency_rootfs_path")
        // Installer-owned paths may use an OS alias above runtime (e.g. /data/user/0).
        // Check these leaves before normalization; neither runtime nor rootfs may itself be a link.
        checkedDirectory(runtime, create = false)
        checkedDirectory(rawRoot, create = false)
        val root = rawRoot.normalize()
        var dependencyRoot = root
        for (part in ROOT.removePrefix("/").split('/')) {
            dependencyRoot = dependencyRoot.resolve(part)
            checkedDirectory(dependencyRoot, create = true)
        }
        for (relative in directories) {
            var directory = dependencyRoot
            for (part in relative.split('/')) {
                directory = directory.resolve(part)
                checkedDirectory(directory, create = true)
            }
        }
        writeReadme(dependencyRoot)
        return dependencyRoot.toFile()
    }

    /** Return only a guest environment overlay; never mutate the caller's host/PRoot environment. */
    fun environment(base: Map<String, String>, defaultPath: String): Map<String, String> {
        val result = LinkedHashMap<String, String>()
        for ((key, value) in base) {
            if (variables.keys.none { it.equals(key, ignoreCase = true) } && !key.equals("PATH", ignoreCase = true)) {
                result[key] = value
            }
        }
        result.putAll(variables)
        val path = base["PATH"] ?: base.entries.firstOrNull { it.key.equals("PATH", ignoreCase = true) }?.value ?: defaultPath
        // Existing official Node/Python and user entries remain ahead of added tools; retain empty entries.
        result["PATH"] = (path.split(':') + bins).distinct().joinToString(":")
        return result
    }

    // l10n:keep guest dependency instructions
    fun instructions(): String = """
        |## 依赖下载、安装与编译目录
        |
        |- 新下载的工具、安装依赖和编译材料统一放在 `$ROOT`，也可用 `${'$'}DSH_DEPENDENCY_ROOT` 引用。这是 App 私有 Ubuntu rootfs 内的目录，不是手机 Download、工作区或 `${'$'}DSH_HOME` 配置目录；正常与恢复配置共用它。
        |- 下载归档放 `${'$'}DSH_DEPENDENCY_ROOT/downloads`，展开源码放 `${'$'}DSH_DEPENDENCY_ROOT/sources`；编译输出放 `${'$'}DSH_DEPENDENCY_ROOT/build`，缓存放 `${'$'}DSH_DEPENDENCY_ROOT/cache`，临时文件放 `${'$'}DSH_DEPENDENCY_ROOT/tmp`（guest 的 `TMPDIR`）。独立可执行工具可放 `${'$'}DSH_DEPENDENCY_ROOT/bin`。
        |- npm 全局工具使用 `NPM_CONFIG_PREFIX`（`$ROOT/npm`）；npm 下载缓存使用 `NPM_CONFIG_CACHE`，node-gyp 头文件使用 `NPM_CONFIG_DEVDIR`，均已指向本目录。项目自己的 `node_modules` 仍按项目包声明与锁文件的契约保留，不将它们强行集中搬移。
        |- Python 优先用独立 venv：`python3 -m venv "${'$'}DSH_DEPENDENCY_ROOT/venvs/NAME"`，再用该 venv 的 pip 安装；适合用户安装时可用 `python3 -m pip install --user PACKAGE`（`PYTHONUSERBASE=$ROOT/python`）。pip 缓存使用 `PIP_CACHE_DIR`；遵循系统包限制，不强制覆盖系统 Python。
        |- Rust 使用 `CARGO_HOME`、`RUSTUP_HOME`；Go 使用 `GOPATH`、`GOMODCACHE`、`GOCACHE`；ccache 使用 `CCACHE_DIR`。这些安装或缓存变量均指向本目录子树。新增 bin 路径追加到既有 `PATH` 后，保持官方 Node/Python 和现有命令优先。
        |- apt 安装的软件包仍由 Ubuntu 系统包管理器管理，沿用系统路径。已有旧目录与文件就地保留，本规则不自动搬移、删除或重置历史依赖。
        |- 本目录在普通引擎升级的 15 项固定替换路径之外，普通升级保留；卸载 App 或清除 App 数据会删除这些私有依赖。重要材料另做备份，不把目录保留等同于所有数据始终有保障。
        |""".trimMargin()

    private fun checkedDirectory(path: Path, create: Boolean) {
        val attributes = try {
            Files.readAttributes(path, BasicFileAttributes::class.java, NOFOLLOW_LINKS)
        } catch (e: NoSuchFileException) {
            if (!create) throw e
            Files.createDirectory(path)
            Files.readAttributes(path, BasicFileAttributes::class.java, NOFOLLOW_LINKS)
        }
        if (!attributes.isDirectory || attributes.isSymbolicLink) throw IOException("dependency_directory:$path")
    }

    private fun shouldWriteReadme(path: Path, content: ByteArray): Boolean {
        val attributes = try {
            Files.readAttributes(path, BasicFileAttributes::class.java, NOFOLLOW_LINKS)
        } catch (_: NoSuchFileException) { return true }
        if (!attributes.isRegularFile || attributes.isSymbolicLink) throw IOException("dependency_readme:$path")
        if (attributes.size() > 64 * 1024) return false
        val buffer = java.nio.ByteBuffer.allocate(64 * 1024 + 1)
        Files.newByteChannel(path, setOf(READ, NOFOLLOW_LINKS)).use { channel ->
            while (buffer.hasRemaining() && channel.read(buffer) >= 0) { }
        }
        if (buffer.position() > 64 * 1024) return false
        val bytes = buffer.array().copyOf(buffer.position())
        return String(bytes, Charsets.UTF_8).startsWith("$README_MARKER\n") && !bytes.contentEquals(content)
    }

    private fun writeReadme(directory: Path) {
        val target = directory.resolve("README.md")
        val content = "$README_MARKER\n# DeepSeek harness 私有依赖目录\n\n删除上面的 managed marker 后，本说明由用户接管，App 保留原文件。\n\n${instructions()}\n".toByteArray(Charsets.UTF_8)
        if (!shouldWriteReadme(target, content)) return
        val temporary = Files.createTempFile(directory, ".dependencies-readme-", ".tmp")
        try {
            Files.newByteChannel(temporary, setOf(WRITE, TRUNCATE_EXISTING, NOFOLLOW_LINKS)).use { channel ->
                Channels.newOutputStream(channel).use { it.write(content) }
            }
            // Recheck ownership immediately before replacing; do not overwrite a newly user-owned README.
            if (!shouldWriteReadme(target, content)) return
            Files.move(temporary, target, ATOMIC_MOVE, REPLACE_EXISTING)
        } finally {
            Files.deleteIfExists(temporary)
        }
    }
}
