package app.dsh.rootruntime

import org.json.JSONArray
import org.json.JSONObject
import java.io.File

internal object RootRuntimeProtocol {
    const val REVISION = "dsh.root-runtime.v1"
    const val REQUEST_MS = 30_000L
    const val MAX_CONFIG = 1024 * 1024
    const val CLEANUP_EXIT = 125
    fun quote(value: String) = "'" + value.replace("'", "'\\''") + "'"
    fun bytes(value: JSONObject) = value.toString().toByteArray(Charsets.UTF_8)
    fun json(bytes: ByteArray): JSONObject {
        require(bytes.size <= MAX_CONFIG)
        return JSONObject(String(bytes, Charsets.UTF_8))
    }
    fun accepted(reply: JSONObject) = reply.optBoolean("ok") && reply.opt("uid") == 0 && reply.optString("revision") == REVISION
}

/** Uses the already composed guest command; never executes the Android PRoot prefix. */
internal data class RootLaunchPlan(
    val rootfs: String,
    val appUid: Int,
    val appGid: Int,
    val marker: String,
    val argv: List<String>,
    val cwd: String,
) {
    fun json(): JSONObject = JSONObject().put("rootfs", rootfs).put("appUid", appUid).put("appGid", appGid)
        .put("marker", marker).put("argv", JSONArray(argv)).put("cwd", cwd)
    companion object {
        fun fromProot(rootfs: File, uid: Int, gid: Int, marker: File, composed: List<String>): RootLaunchPlan {
            val at = composed.indexOf("/usr/bin/env")
            require(at > 0 && composed.getOrNull(at + 1) == "-i") { "root_launch_template" }
            val prefix = composed.take(at)
            val cwdAt = prefix.indexOfLast { it == "-w" || it == "--cwd" }
            val cwd = if (cwdAt >= 0) prefix.getOrNull(cwdAt + 1) ?: "/root" else "/root"
            require(cwd.startsWith('/') && '\u0000' !in cwd)
            val guest = composed.drop(at).toMutableList()
            require(guest.none { it.startsWith("LD_PRELOAD=") || it.startsWith("LD_LIBRARY_PATH=") || it.startsWith("PROOT_") }) { "root_guest_environment" }
            // Android /system/bin/sh scripts and Linux ELF binaries coexist in the chroot.
            guest.addAll(2, listOf("ANDROID_ROOT=/system", "ANDROID_DATA=/data", "ANDROID_ART_ROOT=/apex/com.android.art",
                "ANDROID_I18N_ROOT=/apex/com.android.i18n", "ANDROID_TZDATA_ROOT=/apex/com.android.tzdata"))
            for (key in listOf("BOOTCLASSPATH", "DEX2OATBOOTCLASSPATH")) {
                val value = System.getenv(key) ?: if (key == "BOOTCLASSPATH") System.getProperty("java.boot.class.path") else null
                if (value?.startsWith('/') == true) guest.add(2, "$key=$value")
            }
            val paths = guest.indices.filter { guest[it].startsWith("PATH=") }
            val managedDependencies = guest.any { it == "DSH_DEPENDENCY_ROOT=${app.dsh.runtime.GuestDependencies.ROOT}" }
            if (paths.isNotEmpty() && (paths.size == 1 || managedDependencies)) {
                val atPath = paths.last()
                guest[atPath] = "PATH=" + (guest[atPath].removePrefix("PATH=").split(':') +
                    listOf("/system/bin", "/system/xbin", "/vendor/bin")).distinct().joinToString(":")
            }
            return RootLaunchPlan(rootfs.canonicalPath, uid, gid, marker.absolutePath, guest, cwd)
        }
        fun parse(value: JSONObject): RootLaunchPlan {
            val root = value.getString("rootfs")
            val marker = value.getString("marker")
            val uid = value.getInt("appUid"); val gid = value.getInt("appGid")
            val args = value.getJSONArray("argv")
            val argv = (0 until args.length()).map { args.getString(it) }
            val cwd = value.optString("cwd", "/root")
            require(root.startsWith('/') && marker.startsWith('/') && uid >= 10000 && gid >= 10000)
            require(argv.firstOrNull() == "/usr/bin/env" && argv.getOrNull(1) == "-i" && cwd.startsWith('/'))
            require((listOf(root, marker, cwd) + argv).none { '\u0000' in it })
            return RootLaunchPlan(root, uid, gid, marker, argv, cwd)
        }
    }
}
