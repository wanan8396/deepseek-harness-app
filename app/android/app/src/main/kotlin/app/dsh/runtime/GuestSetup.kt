package app.dsh.runtime

import android.content.Context
import android.net.ConnectivityManager
import android.system.ErrnoException
import android.system.Os
import java.io.File
import java.io.IOException
import java.net.Inet4Address
import java.net.InetAddress

/** Small files inside the rootfs that must reflect the device before each start. */
object GuestSetup {
    private val FALLBACK_DNS = listOf("223.5.5.5", "119.29.29.29", "8.8.8.8")

    private const val AGENTS_MARKER = "<!-- dsh-app:managed"

    // l10n:keep agent prompt
    private val LITE_AGENTS_MD = """
        |<!-- dsh-app:managed — 删除这一行后，DSH App 不再覆盖本文件 -->
        |# 运行环境（DeepSeek harness 手机版）
        |
        |- 你运行在 Android 手机上的 Ubuntu 24.04 环境里（proot，免 Root）。
        |- 这里没有可用的 bubblewrap / Landlock 后端；执行命令使用 `sandbox_permissions: "danger-full-access"`，并说明操作理由。
        |- 默认工作目录是 `/root/workspace`。{STORAGE_LINE}
        |- 已预装 node / npm / pnpm、python3 / pip、git，可按任务需要使用本机文件与命令工具。
        |- 本机引擎每次启动自动检测一次真实 Android Root：取得 UID 0 且启动条件满足时使用 Root，否则使用 PRoot；权限页没有 Root 开关。PRoot 内看到的 uid 0 是模拟身份，不代表 Android Root；以 App 的实际运行模式为准。
        |- Root 模式使用真实 Linux chroot 和私有命名空间，不使用 PRoot 路径翻译；普通命令工具直接在 Root 身份下工作。Android 挂载目录中的脚本可用 `/system/bin/sh /实际路径/script.sh` 执行；保留 Ubuntu 环境的 `/root`、`/usr` 等路径含义。
        |- 启动后的 Root/PRoot 方式保持固定；打开权限页或返回 App 不会反复请求 Root，也不会切换正在运行的对话。此功能不修改网页工具审批。
        |- 当前产品名是 DeepSeek harness；回答中用此名称指代当前 App。
        |- 当前界面是手机本机 DeepSeek harness 网页，不是 Flutter 原生聊天面板；需要网页扩展时使用普通 Harness Web / Cordis 插件。
        |- 本版没有手机操控、跨应用点击输入、悬浮宠物或伙伴模式；不要声称这些能力可用。
        |- 可视化结果使用网页支持的 Markdown、图片链接或生成的 HTML 文件；不要使用仅原生面板支持的 dsh-ui 组件协议。
        |- 手机屏幕小：回复尽量简洁，代码块不要太宽；用用户使用的语言回答。
        |""".trimMargin()

    // l10n:keep agent prompt
    private val LITE_DIAGNOSTICS_SECTION = """
        |
        |## 本机诊断
        |
        |- 用户报障时，可读取本应用发布的诊断快照 `{PATH}`；先核对时间和版本，没有报告时不要假定设备状态。
        |- 日志、API key、token、cookie 和个人文件内容不应原样贴到外部报告；只记录解决问题所需的最小事实。
        |""".trimMargin()

    /** Where the engine finds the current diagnostics snapshot inside the guest. */
    private const val DIAGNOSTICS_FILE = "root/.dsh/dsh-app/diagnostics.md"

    /** Atomically replaces one fixed report and returns its actual host file. */
    fun writeDiagnostics(rootfs: File, markdown: String, safe: Boolean = false): File {
        val path = if (safe) "${SafeMode.HOME.removePrefix("/")}/dsh-app/diagnostics.md" else DIAGNOSTICS_FILE
        val main = File(rootfs, path)
        val dir = main.parentFile ?: throw IOException("no diagnostics directory")
        if (!dir.isDirectory && !dir.mkdirs()) throw IOException("cannot create ${dir.path}")
        val file = main
        val temp = File(dir, ".${file.name}.dsh-tmp")
        try {
            temp.writeText(markdown)
            java.nio.file.Files.move(temp.toPath(), file.toPath(),
                java.nio.file.StandardCopyOption.ATOMIC_MOVE, java.nio.file.StandardCopyOption.REPLACE_EXISTING)
        } finally {
            temp.delete()
        }
        return file
    }

    /** Global DSH instructions ($DSH_HOME/AGENTS.md); left alone once the user removes the marker. */
    fun writeAgentsMd(
        rootfs: File,
        phoneStorage: Boolean,
        rootEngine: Boolean = false,
    ) {
        try {
            val file = File(rootfs, "root/.dsh/AGENTS.md")
            if (file.exists() && !file.readText().startsWith(AGENTS_MARKER)) return
            val instructions = LITE_AGENTS_MD + "\n\n" + GuestDependencies.instructions()
            val environment = if (rootEngine) {
                instructions.replace("Ubuntu 24.04 环境里（proot，免 Root）", "Ubuntu 24.04 环境里（真实 Root / chroot，不运行 PRoot）")
            } else instructions
            val text = environment.replace(
                "{STORAGE_LINE}",
                if (phoneStorage) {
                    // l10n:keep agent prompt
                    "用户已授权访问手机存储：手机内部存储挂载在 `/sdcard`（`/root/手机存储` 是它的快捷方式；相册在 `/sdcard/DCIM`，下载在 `/sdcard/Download`）。改动或删除用户文件前先说明并确认；给用户的产出文件放到 `/sdcard/Download/${PhoneStorage.OUTPUT_SUBDIR}/`。"
                } else {
                    // l10n:keep agent prompt
                    "手机相册、下载等用户文件不在这个环境里，看不到；如需访问，请用户在 App 设置里打开「访问手机文件」。"
                },
            ) + LITE_DIAGNOSTICS_SECTION.replace("{PATH}", "\$DSH_HOME/dsh-app/diagnostics.md")
            file.parentFile?.mkdirs()
            if (!file.exists() || file.readText() != text) file.writeText(text)
        } catch (_: Exception) {
        }
    }

    /** glibc in the guest reads /etc/resolv.conf; Android has none, so mirror the active network's DNS. */
    fun writeResolvConf(context: Context, rootfs: File): DnsConfigReport =
        writeResolvConfFromNetwork(rootfs, {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            cm.getLinkProperties(cm.activeNetwork)?.dnsServers.orEmpty()
        }, Os::rename)

    internal fun writeResolvConfFromNetwork(
        rootfs: File,
        readNetwork: () -> List<InetAddress>,
        replace: (String, String) -> Unit,
    ): DnsConfigReport {
        var networkRead = DnsNetworkRead.READ
        val addresses = try {
            readNetwork().also { if (it.isEmpty()) networkRead = DnsNetworkRead.EMPTY }
        } catch (_: Exception) {
            networkRead = DnsNetworkRead.FAILED
            emptyList()
        }
        return writeResolvConf(rootfs, pickDns(addresses), replace).copy(networkRead = networkRead)
    }

    /** Up to two of the network's servers, IPv4 first, then the public fallbacks: three in all. */
    fun pickDns(addrs: List<InetAddress>): List<String> {
        val network = addrs.filterNot { it.isLinkLocalAddress }
            .sortedBy { if (it is Inet4Address) 0 else 1 }
            .mapNotNull { it.hostAddress?.substringBefore('%') }.distinct().take(2)
        return (network + FALLBACK_DNS).distinct().take(3)
    }

    fun writeResolvConf(rootfs: File, servers: List<String>): DnsConfigReport =
        writeResolvConf(rootfs, servers, Os::rename)

    internal fun writeResolvConf(
        rootfs: File,
        servers: List<String>,
        replace: (String, String) -> Unit,
    ): DnsConfigReport {
        val requested = servers.take(3).toList()
        val text = buildString {
            appendLine("# written by dsh-app from the device's active network")
            servers.forEach { appendLine("nameserver $it") }
            appendLine("options ${DnsConfigReport.OPTIONS}")
        }
        var stage = DnsConfigStage.PREPARE
        try {
            val etc = File(rootfs, "etc")
            if (!etc.isDirectory && !etc.mkdirs() && !etc.isDirectory) throw IOException("Cannot prepare resolver directory")
            val target = File(etc, "resolv.conf")
            stage = DnsConfigStage.READ
            if (target.isFile && target.readText() == text) return DnsConfigReport(DnsConfigOutcome.UNCHANGED, requested)
            // Swapped in whole while DSH runs; also replaces a symlink (e.g. to systemd-resolved) with a plain file.
            val temp = File(etc, ".resolv.conf.dsh-tmp")
            stage = DnsConfigStage.WRITE
            temp.writeText(text)
            stage = DnsConfigStage.REPLACE
            replace(temp.path, target.path)
            return DnsConfigReport(DnsConfigOutcome.WRITTEN, requested)
        } catch (e: Exception) {
            val error = when (e) {
                is ErrnoException -> DnsConfigError.NATIVE
                is SecurityException -> DnsConfigError.SECURITY
                is IOException -> DnsConfigError.IO
                else -> DnsConfigError.OTHER
            }
            return DnsConfigReport(DnsConfigOutcome.FAILED, requested, stage, error, (e as? ErrnoException)?.errno)
        }
    }
}
