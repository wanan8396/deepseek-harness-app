package app.dsh.runtime

import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.nio.file.LinkOption

/**
 * User-editable Web bridges, read from the guest's `$DSH_HOME/dsh-app/web/`.
 *
 * The shell ships the bridges under assets/web; a file of the same name here
 * replaces it, so a bridge can change without rebuilding the APK. Only the
 * bridge names the app already knows are readable, the file must be a regular
 * file, and both the directory and the file must stay inside the guest home.
 * Nothing here writes: an absent file means "use the bundled asset".
 */
object WebOverrides {
    /** Guest home that owns the override directory; matches the diagnostics location. */
    private const val GUEST_HOME = "/root/.dsh"
    private const val DIRECTORY = "dsh-app/web"

    /** Bridges a build already injects; a name outside this set is never read. */
    val BRIDGES = setOf(
        "open", "back", "sidebar", "modal", "appearance", "state",
        "phone", "phone_layout", "header-menus", "settings_document", "session_delete",
    )

    const val MAX_BYTES = 512 * 1024

    fun directory(rootfs: File): File = File(rootfs, "$GUEST_HOME/$DIRECTORY")

    /**
     * The override for [bridge], or null when the user has not written one.
     * Throws only for a path that escapes the override directory; a missing,
     * oversized or unreadable file is reported as null so the bundled asset wins.
     */
    fun read(rootfs: File, bridge: String): String? {
        require(bridge in BRIDGES) { "unknown web bridge" }
        val root = directory(rootfs)
        // The whole chain must be a real directory: a symlinked home, dsh-app or
        // web/ would let a link decide what this process reads.
        if (!root.isDirectory || Files.isSymbolicLink(root.toPath())) return null
        val file = File(root, "$bridge.js")
        val path = file.toPath()
        if (Files.isSymbolicLink(path)) return null
        if (!file.isFile || file.length() > MAX_BYTES) return null
        val canonicalRoot = root.canonicalPath + File.separator
        val canonical = try { file.canonicalFile } catch (_: IOException) { return null }
        if (!canonical.path.startsWith(canonicalRoot)) return null
        return try {
            file.readText(Charsets.UTF_8)
        } catch (_: IOException) {
            null
        }
    }

    /** Names with an override present, for the diagnostics page. */
    fun present(rootfs: File): List<String> = BRIDGES.filter { read(rootfs, it) != null }.sorted()

    /** Ensures the directory exists so a user can drop a file in without guessing the path. */
    fun prepare(rootfs: File): File {
        val root = directory(rootfs)
        if (!root.isDirectory && !root.mkdirs() && !root.isDirectory) throw IOException("cannot create ${root.path}")
        // Only the leaf is created here; a linked ancestor is refused by read().
        check(Files.exists(root.toPath(), LinkOption.NOFOLLOW_LINKS)) { "web override directory is a link" }
        return root
    }
}
