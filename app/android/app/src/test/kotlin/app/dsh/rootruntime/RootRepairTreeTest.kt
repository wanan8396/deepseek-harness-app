package app.dsh.rootruntime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.IOException
import java.nio.file.Files
import java.nio.file.LinkOption.NOFOLLOW_LINKS
import java.nio.file.Path

class RootRepairTreeTest {
    @get:Rule val temp = TemporaryFolder()
    private val uid = 10123

    private fun stat(path: Path): RootRepairTree.Entry {
        val a = Files.readAttributes(path, "unix:dev,ino,mode,nlink,isDirectory,isSymbolicLink", NOFOLLOW_LINKS)
        return RootRepairTree.Entry(a.getValue("dev") as Long, a.getValue("ino") as Long, 0,
            (a.getValue("nlink") as Number).toLong(), a.getValue("mode") as Int,
            a.getValue("isDirectory") as Boolean, a.getValue("isSymbolicLink") as Boolean)
    }

    @Test fun usesOneMetadataReadPerFilePerPassAndRepairsDirectoriesLast() {
        val root = temp.newFolder().toPath()
        val dir = Files.createDirectory(root.resolve("dir"))
        val file = Files.createFile(dir.resolve("file"))
        val reads = mutableMapOf<Path, Int>()
        val order = mutableListOf<Path>()
        RootRepairTree.repair(root, uid, { path -> reads[path] = (reads[path] ?: 0) + 1; stat(path) },
            { path, _ -> order.add(path) })
        assertEquals(2, reads.getValue(file))
        assertEquals(listOf(file, dir, root), order)
    }

    @Test fun rejectsExternalHardLinksBeforeAnyRepair() {
        val root = temp.newFolder().toPath()
        val outside = temp.newFile().toPath()
        Files.createLink(root.resolve("external"), outside)
        Files.createFile(root.resolve("ordinary"))
        expectFailure("root_cleanup_hardlink") {
            RootRepairTree.repair(root, uid, ::stat) { _, _ -> error("mutation before validation") }
        }
    }

    @Test fun acceptsInternalHardLinksAndDoesNotDescendIntoSymlinks() {
        val root = temp.newFolder().toPath()
        val file = Files.createFile(root.resolve("file"))
        val alias = Files.createLink(root.resolve("alias"), file)
        val outside = temp.newFolder().toPath()
        val outsideFile = Files.createFile(outside.resolve("file"))
        val link = Files.createSymbolicLink(root.resolve("link"), outside)
        val restored = mutableMapOf<Path, RootRepairTree.Entry>()
        RootRepairTree.repair(root, uid, ::stat) { path, entry -> restored[path] = entry }
        assertEquals(setOf(root, file, alias, link), restored.keys)
        assertTrue(restored.getValue(link).symlink)
        assertTrue(outsideFile !in restored)
    }

    @Test fun rejectsDifferentDeviceAndDirectoryIdentityChanges() {
        val root = temp.newFolder().toPath()
        val folder = Files.createDirectory(root.resolve("folder"))
        expectFailure("root_cleanup_mount") {
            RootRepairTree.repair(root, uid, { path -> stat(path).let { if (path == folder) it.copy(device = it.device + 1) else it } },
                { _, _ -> error("mutation before validation") })
        }
        var reads = 0
        expectFailure("root_cleanup_changed") {
            RootRepairTree.repair(root, uid, { path -> stat(path).let {
                if (path == folder && ++reads == 2) it.copy(inode = it.inode + 1) else it
            } }, { _, _ -> error("mutation before validation") })
        }
    }

    @Test fun secondPassReadsAndRepairsNewFilesAndFreshDirectoryMode() {
        val root = temp.newFolder().toPath()
        val file = root.resolve("new")
        var rootReads = 0
        val restored = mutableMapOf<Path, RootRepairTree.Entry>()
        RootRepairTree.repair(root, uid, { path ->
            if (path == root && ++rootReads == 5) Files.createFile(file)
            val entry = stat(path)
            if (path == root && rootReads == 7) entry.copy(mode = 448) else entry
        }, { path, entry -> restored[path] = entry })
        assertTrue(file in restored)
        assertEquals(448, restored.getValue(root).mode)
    }

    @Test fun hardLinkAddedBetweenPassesRemainsBlocked() {
        val root = temp.newFolder().toPath()
        val file = Files.createFile(root.resolve("first"))
        val outside = temp.newFolder().toPath()
        var rootReads = 0
        expectFailure("root_cleanup_hardlink") {
            RootRepairTree.repair(root, uid, { path ->
                if (path == root && ++rootReads == 5) Files.createLink(outside.resolve("new"), file)
                stat(path)
            }, { _, _ -> error("unexpected chown for a new external hard link") })
        }
    }

    private fun expectFailure(message: String, block: () -> Unit) {
        val failure = runCatching(block).exceptionOrNull()
        assertTrue(failure is IOException)
        assertEquals(message, failure?.message)
    }
}
