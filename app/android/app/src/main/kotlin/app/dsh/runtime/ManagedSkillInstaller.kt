package app.dsh.runtime

import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/** Validated bundled-guide input for native startup synchronization. */
internal class ManagedSkillRequest private constructor(
    val expectedRoot: String,
    val name: String,
    val files: Map<String, String>,
) {
    companion object {
        const val MAX_FILES = 64
        const val MAX_FILE_BYTES = 512 * 1024
        const val MAX_BYTES = 1024 * 1024
        private val names = setOf("deepseek-harness-guide")
        private val path = Regex("^[A-Za-z0-9_-][A-Za-z0-9._-]*(/[A-Za-z0-9_-][A-Za-z0-9._-]*)*$")

        /** Bounded bundle checks; the installer separately enforces UTF-8 byte budgets. */
        fun create(expectedRoot: String, name: String, files: Map<String, String>): ManagedSkillRequest? {
            if (expectedRoot.isEmpty() || expectedRoot.length > 4096 ||
                name !in names || files.size !in 1..MAX_FILES) return null
            val checked = LinkedHashMap<String, String>()
            var units = 0
            for ((key, value) in files) {
                if (key.length > 512 || !path.matches(key) || value.length > MAX_FILE_BYTES) return null
                units += value.length
                if (units > MAX_BYTES) return null
                checked[key] = value
            }
            if (!checked.containsKey("SKILL.md")) return null
            return ManagedSkillRequest(expectedRoot, name, checked)
        }
    }
}

internal data class ManagedSkillOutcome(val result: String? = null, val reason: String? = null)

/**
 * File transaction on RuntimeController's worker, also used by rootfs activation/reset.
 * Cancellation stops later commits. An already-started filesystem operation can finish;
 * it is not rollback. SKILL.md is committed last so a first partial install stays hidden.
 */
internal object ManagedSkillInstaller {
    private const val MARKER = "# deepseek-harness:managed"
    private val frontMatter = Regex("^---\\r?\\n([\\s\\S]*?)\\r?\\n---")

    private fun managed(text: String): Boolean = frontMatter.find(text)?.groupValues?.get(1)
        ?.lineSequence()?.any { it.trimStart().startsWith(MARKER) } == true

    fun install(root: File, request: ManagedSkillRequest, current: () -> Boolean): ManagedSkillOutcome {
        fun checkCurrent() { if (!current()) throw Retired() }
        try {
            checkCurrent()
            if (File(request.expectedRoot).canonicalFile != root.canonicalFile) return ManagedSkillOutcome(reason = "stale")
            val bytes = LinkedHashMap<String, ByteArray>()
            var total = 0
            for ((path, text) in request.files) {
                val encoder = Charsets.UTF_8.newEncoder().onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT)
                val encoded = encoder.encode(java.nio.CharBuffer.wrap(text))
                val data = ByteArray(encoded.remaining()).also { encoded.get(it) }
                total += data.size
                if (data.size > ManagedSkillRequest.MAX_FILE_BYTES || total > ManagedSkillRequest.MAX_BYTES) {
                    return ManagedSkillOutcome(reason = "invalid")
                }
                bytes[path] = data
            }
            if (!managed(request.files.getValue("SKILL.md"))) return ManagedSkillOutcome(reason = "invalid")
            checkCurrent()
            val home = File(root, "root/.dsh")
            if (!home.isDirectory) return ManagedSkillOutcome("noHome")
            val dir = File(home, "skills/${request.name}")
            val rootPath = root.canonicalFile.toPath()
            val dirPath = dir.canonicalFile.toPath()
            // Fail closed for an escaped managed directory/file. This is not a sandbox against
            // another writer changing symlinks concurrently; rootfs swaps are serialized above.
            if (!dirPath.startsWith(rootPath)) return ManagedSkillOutcome("userOwned")
            for (path in bytes.keys) {
                if (!File(dir, path).canonicalFile.toPath().startsWith(dirPath) ||
                    !File(dir, "$path.deepseek-harness-tmp").canonicalFile.toPath().startsWith(dirPath)) {
                    return ManagedSkillOutcome("userOwned")
                }
            }
            val skill = File(dir, "SKILL.md")
            val existed = skill.exists()
            if (existed && readText(skill, ManagedSkillRequest.MAX_FILE_BYTES)?.let(::managed) != true) {
                return ManagedSkillOutcome("userOwned")
            }
            var changed = false
            val order = bytes.keys.filter { it != "SKILL.md" } + "SKILL.md"
            for (path in order) {
                checkCurrent()
                val file = File(dir, path)
                val data = bytes.getValue(path)
                if (readText(file, data.size + 3) == request.files.getValue(path)) continue
                checkCurrent()
                val parent = file.parentFile!!
                if (!parent.isDirectory && !parent.mkdirs() && !parent.isDirectory) {
                    throw java.io.IOException("cannot create skill directory")
                }
                val tmp = File(parent, "${file.name}.deepseek-harness-tmp")
                try {
                    checkCurrent()
                    FileOutputStream(tmp).use { stream -> stream.write(data); stream.fd.sync() }
                    checkCurrent()
                    Files.move(tmp.toPath(), file.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
                    changed = true
                } finally {
                    // A failed/retired stage must not poison the next run's managed install.
                    if (tmp.exists()) tmp.delete()
                }
            }
            return ManagedSkillOutcome(if (!existed) "installed" else if (changed) "updated" else "unchanged")
        } catch (_: Retired) {
            return ManagedSkillOutcome(reason = "cancelled")
        } catch (_: Exception) {
            // No file contents, token, path or filesystem error text crosses into runtime logs.
            return ManagedSkillOutcome(reason = "io")
        }
    }

    /** Bounded, strict UTF-8, with the same leading-BOM behavior as Dart File.readAsString. */
    private fun readText(file: File, limit: Int): String? = try {
        file.inputStream().use { stream ->
            val out = ByteArrayOutputStream(minOf(limit, 8192))
            val buffer = ByteArray(8192)
            while (true) {
                val count = stream.read(buffer, 0, minOf(buffer.size, limit + 1 - out.size()))
                if (count < 0) break
                out.write(buffer, 0, count)
                if (out.size() > limit) return null
            }
            val decoder = Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
            decoder.decode(ByteBuffer.wrap(out.toByteArray())).toString().removePrefix("\uFEFF")
        }
    } catch (_: Exception) { null }

    private class Retired : RuntimeException()
}
