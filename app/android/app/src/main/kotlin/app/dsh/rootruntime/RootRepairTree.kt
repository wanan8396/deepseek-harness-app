package app.dsh.rootruntime

import java.io.IOException
import java.nio.file.DirectoryStream
import java.nio.file.Files
import java.nio.file.Path
import java.util.ArrayDeque

/** Two full passes using one lstat per ordinary entry per pass. */
internal object RootRepairTree {
    data class Entry(val device: Long, val inode: Long, val uid: Int, val links: Long,
        val mode: Int, val directory: Boolean, val symlink: Boolean)
    private data class Frame(val path: Path, val entry: Entry, val stream: DirectoryStream<Path>, val children: Iterator<Path>)

    fun repair(root: Path, uid: Int, stat: (Path) -> Entry, restore: (Path, Entry) -> Unit) {
        val rootEntry = stat(root)
        if (!rootEntry.directory || rootEntry.symlink) throw IOException("root_cleanup_path")
        fun inspect(path: Path): Entry {
            val entry = stat(path)
            if (entry.device != rootEntry.device) throw IOException("root_cleanup_mount")
            return entry
        }
        fun walk(file: (Path, Entry) -> Unit, directory: (Path, Entry) -> Unit) {
            val stack = ArrayDeque<Frame>()
            fun enter(path: Path, before: Entry) {
                val stream = Files.newDirectoryStream(path)
                try {
                    // Like walkFileTree, this opens by path. Only descend into
                    // lstat-observed directories and verify identity after open.
                    checkDirectory(before, inspect(path))
                    stack.addLast(Frame(path, before, stream, stream.iterator()))
                } catch (error: Throwable) {
                    runCatching { stream.close() }
                    throw error
                }
            }
            try {
                val current = inspect(root)
                checkDirectory(rootEntry, current)
                enter(root, current)
                while (stack.isNotEmpty()) {
                    val frame = stack.last
                    if (frame.children.hasNext()) {
                        val path = frame.children.next()
                        val entry = inspect(path)
                        if (entry.directory && !entry.symlink) enter(path, entry) else file(path, entry)
                    } else {
                        stack.removeLast()
                        frame.stream.close()
                        val currentDirectory = inspect(frame.path)
                        checkDirectory(frame.entry, currentDirectory)
                        directory(frame.path, currentDirectory)
                    }
                }
            } finally {
                while (stack.isNotEmpty()) runCatching { stack.removeLast().stream.close() }
            }
        }
        val counts = HashMap<Long, Long>()
        val totals = HashMap<Long, Long>()
        walk(file = { _, entry ->
            if (entry.uid != uid && entry.links > 1) {
                counts.merge(entry.inode, 1L, Long::plus)
                val previous = totals.put(entry.inode, entry.links)
                if (previous != null && previous != entry.links) throw IOException("root_cleanup_changed")
            }
        }, directory = { _, _ -> })
        if (counts != totals) throw IOException("root_cleanup_hardlink")

        walk(file = { path, entry ->
            if (entry.uid != uid) {
                if (entry.links > 1 && counts[entry.inode] != entry.links) throw IOException("root_cleanup_hardlink")
                restore(path, entry)
            }
        }, directory = { path, entry -> if (entry.uid != uid) restore(path, entry) })
    }

    private fun checkDirectory(expected: Entry, current: Entry) {
        if (!current.directory || current.symlink || expected.inode != current.inode || expected.device != current.device) {
            throw IOException("root_cleanup_changed")
        }
    }
}
