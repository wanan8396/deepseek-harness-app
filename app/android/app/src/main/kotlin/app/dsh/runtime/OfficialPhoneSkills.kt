package app.dsh.runtime

import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.nio.file.Files

/** Current bundled guide synchronization, serialized with runtime startup. */
internal object OfficialPhoneSkills {
    private const val GUIDE = "deepseek-harness-guide"
    private const val ASSETS = "flutter_assets/assets/skills/dsh-app-guide/"
    private val assetName = Regex("^[A-Za-z0-9_-]+\\.md$")
    data class Result(val guide: String)

    fun sync(root: File, readAsset: (String) -> String, current: () -> Boolean): Result {
        fun checkCurrent() { if (!current()) throw IOException("official_phone_skills_cancelled") }
        try {
            checkCurrent()
            val manifest = JSONObject(readAsset(ASSETS + "manifest.json"))
            require(manifest.getString("name") == GUIDE)
            val entries = manifest.getJSONObject("files")
            require(entries.length() in 1..ManagedSkillRequest.MAX_FILES)
            val files = linkedMapOf<String, String>()
            for (name in entries.keys()) {
                require(assetName.matches(name))
                val target = entries.getString(name)
                require(!files.containsKey(target))
                files[target] = readAsset(ASSETS + name)
            }
            val request = ManagedSkillRequest.create(root.absolutePath, GUIDE, files)
                ?: throw IOException("official_phone_skills_invalid")
            val home = File(root, "root/.dsh")
            if (!plainPath(root, home)) return Result("userOwned")
            checkCurrent()
            if (!home.isDirectory && !home.mkdirs() && !home.isDirectory) throw IOException("official_phone_skills_io")
            val guideDir = File(home, "skills/$GUIDE")
            val guidePaths = files.keys.map { File(guideDir, it) } +
                files.keys.map { File(guideDir, "$it.deepseek-harness-tmp") }
            if (guidePaths.any { !plainPath(root, it) }) return Result("userOwned")
            checkCurrent()
            val outcome = ManagedSkillInstaller.install(root, request, current)
            if (outcome.reason != null) throw IOException("official_phone_skills_${outcome.reason}")
            return Result(outcome.result ?: throw IOException("official_phone_skills_io"))
        } catch (failure: Exception) {
            if (failure is IOException && failure.message?.matches(Regex("official_phone_skills_[a-z_]+")) == true) throw failure
            throw IOException("official_phone_skills_io")
        }
    }

    private fun plainPath(root: File, target: File): Boolean {
        val base = root.toPath().toAbsolutePath().normalize()
        val path = target.toPath().toAbsolutePath().normalize()
        if (!path.startsWith(base) || Files.isSymbolicLink(base)) return false
        var cursor = base
        for (part in base.relativize(path)) {
            cursor = cursor.resolve(part)
            if (Files.isSymbolicLink(cursor)) return false
        }
        return true
    }
}
