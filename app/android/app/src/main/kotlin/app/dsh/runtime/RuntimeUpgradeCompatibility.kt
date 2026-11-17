package app.dsh.runtime

import java.io.File
import java.nio.file.Files
import org.json.JSONObject

internal fun checkEngineCompatibility(baseDir: File, raw: JSONObject, version: String, abi: String): EngineUpgradeSpec {
    val rootfs = File(baseDir, "rootfs")
    val staging = File(baseDir, "staging")
    if (Files.isSymbolicLink(rootfs.toPath()) || File(baseDir, "home.carry").exists() ||
        File(baseDir, "rootfs.old").exists()) throw RuntimeUpgradeBlocked("legacy_interrupted")
    val next = parseUpgrade(raw)
    val shipped = readRuntimeInfo(staging)
    if (parseUpgrade(shipped) != next || shipped.optString("runtimeVersion") != version) {
        throw RuntimeUpgradeBlocked("manifest")
    }
    val previous = readRuntimeInfo(rootfs)
    if (previous.optString("abi") != abi || shipped.optString("abi") != abi ||
        osIdentity(rootfs) != osIdentity(staging)) throw RuntimeUpgradeBlocked("base")
    val installedSystem = try { previous.getJSONObject("upgrade") }
        catch (_: Exception) { throw RuntimeUpgradeBlocked("manifest") }
    // Only the incoming manifest grants mutation scope. The installed manifest
    // proves system identity; its former path list never drives this transaction.
    if (installedSystem.optInt("schema") != 1) throw RuntimeUpgradeBlocked("manifest")
    if (installedSystem.optString("baseId") != next.baseId ||
        installedSystem.optString("ubuntuVersion") != next.ubuntuVersion) throw RuntimeUpgradeBlocked("base")
    return next
}

private fun readRuntimeInfo(tree: File): JSONObject = try {
    JSONObject(File(tree, "etc/dsh-app/runtime.json").readText())
} catch (_: Exception) {
    throw RuntimeUpgradeBlocked("manifest")
}

private fun parseUpgrade(json: JSONObject): EngineUpgradeSpec = try {
    val upgrade = json.getJSONObject("upgrade")
    if (upgrade.getInt("schema") != 1) throw RuntimeUpgradeBlocked("manifest")
    val paths = upgrade.getJSONArray("paths")
    EngineUpgradeSpec(upgrade.getString("baseId"), upgrade.getString("ubuntuVersion"),
        List(paths.length()) { paths.getString(it) }).also { it.validate() }
} catch (_: Exception) {
    throw RuntimeUpgradeBlocked("manifest")
}

private fun osIdentity(tree: File): List<String> = try {
    val rows = File(tree, "etc/os-release").readLines()
    listOf("ID", "VERSION_ID").map { key ->
        rows.single { it.startsWith("$key=") }.substringAfter('=').trim().trim('"', '\'')
    }
} catch (_: Exception) {
    throw RuntimeUpgradeBlocked("base")
}
