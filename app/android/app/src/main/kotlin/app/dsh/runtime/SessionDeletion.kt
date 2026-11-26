package app.dsh.runtime

import java.io.File
import java.io.IOException
import java.nio.file.Files

/**
 * Deleting one engine Session from the shell.
 *
 * The engine has no delete API: archiving only adds the id to a set and leaves
 * `session.v4.jsonl.zstd` in place. The Session directory is on the app's own
 * filesystem, so the shell can remove it directly. The engine's SQLite search
 * index is left alone — its `_reconcile` drops rows whose directory is gone.
 *
 * Every accepted request names one existing project directory and one Session
 * id of the engine's shape. Resolved paths must stay inside
 * `$DSH_HOME/sessions`, no dot entry or `_mutations` is ever a target, and a
 * project that is itself a symlink is refused: the deletion never follows a
 * link out of the sessions tree.
 */
object SessionDeletion {
    private const val GUEST_HOME = "/root/.dsh"
    private const val SESSIONS = "sessions"

    /**
     * The three id shapes the engine writes as Session directories: a UUID, the
     * same UUID behind a `session-` prefix, or a hex digest (32, 40 or 64).
     * A wrong shape here would silently make real Sessions undeletable.
     */
    private val SESSION_ID = Regex(
        "^(?:session-)?(?:" +
            "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}" +
            "|[0-9a-fA-F]{32}|[0-9a-fA-F]{40}|[0-9a-fA-F]{64})" +
            ")$",
    )

    /** What one deletion removed. */
    data class Removed(val project: String, val sessionId: String, val bytes: Long, val files: Int)

    fun sessionsRoot(rootfs: File): File = File(rootfs, "$GUEST_HOME/$SESSIONS")

    /** True for a name the deletion accepts as a project directory. */
    internal fun validProject(project: String): Boolean =
        project.isNotEmpty() && project.length <= 200 && !project.startsWith(".") &&
            '/' !in project && '\\' !in project

    /**
     * The projects on disk, each with its Session ids. Only what [delete] would
     * accept is listed, so a page never offers an entry that then fails.
     */
    fun list(rootfs: File): Map<String, List<String>> {
        val root = sessionsRoot(rootfs)
        if (!root.isDirectory || Files.isSymbolicLink(root.toPath())) return emptyMap()
        val out = sortedMapOf<String, List<String>>()
        for (project in root.listFiles().orEmpty().sortedBy { it.name }) {
            if (!project.isDirectory || !validProject(project.name)) continue
            if (Files.isSymbolicLink(project.toPath())) continue
            val ids = project.listFiles().orEmpty()
                .filter { it.isDirectory && it.name != "_mutations" && SESSION_ID.matches(it.name) }
                .filterNot { Files.isSymbolicLink(it.toPath()) }
                .map { it.name }
                .sorted()
            if (ids.isNotEmpty()) out[project.name] = ids
        }
        return out
    }

    /**
     * The project that currently holds [sessionId], or null when none does.
     * A Session id is unique, so the caller does not have to know its project;
     * the same checks [delete] applies decide which one is reported.
     */
    fun projectOf(rootfs: File, sessionId: String): String? {
        if (!SESSION_ID.matches(sessionId)) return null
        val root = sessionsRoot(rootfs)
        if (!root.isDirectory || Files.isSymbolicLink(root.toPath())) return null
        for (project in root.listFiles().orEmpty().sortedBy { it.name }) {
            if (!project.isDirectory || !validProject(project.name)) continue
            if (Files.isSymbolicLink(project.toPath())) continue
            val target = File(project, sessionId)
            if (!target.isDirectory || Files.isSymbolicLink(target.toPath())) continue
            if (!target.canonicalPath.startsWith(project.canonicalPath + File.separator)) continue
            return project.name
        }
        return null
    }

    /**
     * Removes exactly one Session directory and reports what went. Anything the
     * listing would not have offered is refused; a refusal changes nothing.
     */
    fun delete(rootfs: File, project: String, sessionId: String): Removed {
        require(validProject(project)) { "session_project_invalid" }
        require(SESSION_ID.matches(sessionId)) { "session_id_invalid" }

        val root = sessionsRoot(rootfs)
        if (!root.isDirectory || Files.isSymbolicLink(root.toPath())) throw IOException("sessions_unavailable")

        val projectDir = File(root, project)
        // A linked project would let this deletion act on a directory outside sessions.
        if (Files.isSymbolicLink(projectDir.toPath()) || !projectDir.isDirectory) {
            throw IOException("session_project_unknown")
        }
        if (!projectDir.canonicalPath.startsWith(root.canonicalPath + File.separator)) {
            throw IOException("session_project_escaped")
        }

        val target = File(projectDir, sessionId)
        if (Files.isSymbolicLink(target.toPath()) || !target.isDirectory) throw IOException("session_unknown")
        if (!target.canonicalPath.startsWith(projectDir.canonicalPath + File.separator)) {
            throw IOException("session_escaped")
        }

        var files = 0
        var bytes = 0L
        target.walkTopDown().forEach { entry ->
            if (entry.isFile && !Files.isSymbolicLink(entry.toPath())) {
                files++
                bytes += entry.length()
            }
        }

        // The directory was built from a validated id inside a validated
        // project, so this removes that Session and nothing beside it.
        target.deleteRecursivelySafely()
        if (target.exists()) throw IOException("session_delete_incomplete")
        return Removed(project, sessionId, bytes, files)
    }
}
