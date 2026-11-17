package app.dsh.runtime

import java.io.ByteArrayOutputStream
import java.io.File
import java.net.URI
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.nio.file.Files
import java.nio.file.LinkOption.NOFOLLOW_LINKS
import java.nio.file.NoSuchFileException
import java.nio.file.StandardOpenOption.READ
import java.nio.file.attribute.BasicFileAttributes

/** A bounded, read-only view of the configuration belonging to a captured official launch. */
internal object LocalSettingsDocument {
    const val MAX_BYTES = 512 * 1024
    private const val NORMAL_HOME = "/root/.dsh"
    private const val RESCUE_HOME = "/var/lib/dsh-app/safe-mode/home"

    class Failure(val code: String) : Exception(code)
    data class Location(val home: String, val profile: String) {
        val guestPath: String get() = "$home/profiles/$profile/cordis.patch.yml"
    }
    data class Document(val location: Location, val text: String)

    /** Recognize only the actual official launcher, never guess a custom profile's path. */
    fun location(argv: List<String>, guestEnv: Map<String, String>): Location? {
        val envAt = argv.indexOf("/usr/bin/env")
        if (envAt < 0 || argv.getOrNull(envAt + 1) != "-i" || argv.count { it == "{GUEST_ENV}" } != 1) return null
        val values = LinkedHashMap<String, String>()
        var at = envAt + 2
        while (at < argv.size) {
            val arg = argv[at]
            if (arg == "{GUEST_ENV}") values.putAll(guestEnv)
            else if (arg.matches(Regex("[A-Za-z_][A-Za-z0-9_]*=.*", RegexOption.DOT_MATCHES_ALL))) {
                val split = arg.indexOf('='); values[arg.substring(0, split)] = arg.substring(split + 1)
            } else break
            at++
        }
        if (argv.drop(at).size != 3 || argv[at] != "/bin/sh" || argv[at + 1] != "-c") return null
        val script = argv[at + 2]
        // The optional pid-file command is launcher-owned; no shell overlays or additional commands.
        val command = script.removePrefix("echo $$ > /tmp/dsh-web.pid; ")
        val pattern = Regex("^exec /usr/local/bin/dsh (web|--profile dsh-app-safe --from-default-profile web) --host 127\\.0\\.0\\.1 --port (?:\\{PORT\\}|[0-9]{1,5}) --no-open$")
        val match = pattern.matchEntire(command) ?: return null
        val safe = match.groupValues[1] != "web"
        val home = values["DSH_HOME"] ?: return null
        if (home != if (safe) RESCUE_HOME else NORMAL_HOME) return null
        return Location(home, if (safe) "dsh-app-safe" else "web")
    }

    fun sameOrigin(expected: String, supplied: String): Boolean = try {
        val a = URI(expected); val b = URI(supplied)
        a.scheme == "http" && a.host == "127.0.0.1" && a.port > 0 &&
            b.scheme == a.scheme && b.host == a.host && b.port == a.port &&
            a.rawUserInfo == null && b.rawUserInfo == null && b.rawQuery == null && b.rawFragment == null &&
            b.path in listOf("", "/")
    } catch (_: Exception) { false }

    fun read(rootfs: File, location: Location): Document {
        if (location !in listOf(Location(NORMAL_HOME, "web"), Location(RESCUE_HOME, "dsh-app-safe"))) throw Failure("config_document_unsupported")
        try {
            val root = rootfs.toPath().toAbsolutePath().normalize()
            if (Files.isSymbolicLink(root) || !Files.isDirectory(root, NOFOLLOW_LINKS)) throw Failure("config_document_path")
            val leaf = root.resolve(location.guestPath.removePrefix("/"))
            val directories = ArrayList<Pair<java.nio.file.Path, BasicFileAttributes>>()
            var cursor = root
            directories += cursor to Files.readAttributes(cursor, BasicFileAttributes::class.java, NOFOLLOW_LINKS)
            for (part in root.relativize(leaf).toList().dropLast(1)) {
                cursor = cursor.resolve(part)
                val attrs = Files.readAttributes(cursor, BasicFileAttributes::class.java, NOFOLLOW_LINKS)
                if (!attrs.isDirectory || attrs.isSymbolicLink) throw Failure("config_document_path")
                directories += cursor to attrs
            }
            val before = Files.readAttributes(leaf, BasicFileAttributes::class.java, NOFOLLOW_LINKS)
            if (!before.isRegularFile || before.isSymbolicLink) throw Failure("config_document_path")
            if (before.size() > MAX_BYTES) throw Failure("config_document_too_large")
            val bytes = ByteArrayOutputStream()
            Files.newByteChannel(leaf, setOf(READ, NOFOLLOW_LINKS)).use { channel ->
                val buffer = ByteBuffer.allocate(8192)
                while (true) {
                    buffer.clear()
                    val count = channel.read(buffer)
                    if (count < 0) break
                    if (bytes.size() + count > MAX_BYTES) throw Failure("config_document_too_large")
                    bytes.write(buffer.array(), 0, count)
                }
            }
            val after = Files.readAttributes(leaf, BasicFileAttributes::class.java, NOFOLLOW_LINKS)
            if (after.isSymbolicLink || !after.isRegularFile || before.fileKey() != after.fileKey() ||
                before.size() != after.size() || before.lastModifiedTime() != after.lastModifiedTime()) throw Failure("config_document_stale")
            for ((path, original) in directories) {
                val now = Files.readAttributes(path, BasicFileAttributes::class.java, NOFOLLOW_LINKS)
                if (!now.isDirectory || now.isSymbolicLink || now.fileKey() != original.fileKey()) throw Failure("config_document_stale")
            }
            val text = try {
                Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes.toByteArray())).toString()
            } catch (_: java.nio.charset.CharacterCodingException) { throw Failure("config_document_utf8") }
            return Document(location, text)
        } catch (e: Failure) { throw e }
        catch (_: NoSuchFileException) { throw Failure("config_document_missing") }
        catch (_: Exception) { throw Failure("config_document_unreadable") }
    }
}
