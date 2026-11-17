package app.dsh.runtime

import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.nio.file.LinkOption.NOFOLLOW_LINKS
import java.nio.file.attribute.PosixFilePermissions
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class GuestDependenciesTest {
    @get:Rule val temp = TemporaryFolder()
    // Contract literals are independent of the implementation's directory/variable tables.
    private val relativeRoot = "root/.local/share/deepseek-harness/dependencies"
    private fun dependencyRoot(rootfs: File) = File(rootfs, relativeRoot)
    private fun expectPathFailure(action: () -> Unit) {
        try { action(); fail("Expected a path collision") } catch (_: IOException) { }
    }
    private fun seed(root: File, relative: String, bytes: ByteArray = "keep\n".toByteArray()): File =
        File(root, relative).apply { parentFile.mkdirs(); writeBytes(bytes) }

    @Test fun fixedRootAndExactRealDirectoryTreeAreOutsideEngineAndProfilePaths() {
        assertEquals("/root/.local/share/deepseek-harness/dependencies", GuestDependencies.ROOT)
        val rootfs = temp.newFolder("rootfs")
        assertEquals(dependencyRoot(rootfs), GuestDependencies.prepare(rootfs))
        val expected = setOf(
            "bin", "npm", "npm/bin", "python", "python/bin", "venvs", "downloads", "sources", "build", "tmp",
            "cache", "cache/npm", "cache/node-gyp", "cache/pip", "cache/go-mod", "cache/go-build", "cache/ccache",
            "cargo", "cargo/bin", "rustup", "go", "go/bin",
        )
        val directory = dependencyRoot(rootfs)
        val actual = directory.walkTopDown().filter { it != directory && it.isDirectory }
            .map { it.relativeTo(directory).invariantSeparatorsPath }.toSet()
        assertEquals(expected, actual)
        for (name in expected) {
            assertTrue(name, Files.isDirectory(File(directory, name).toPath(), NOFOLLOW_LINKS))
            assertFalse(name, Files.isSymbolicLink(File(directory, name).toPath()))
        }
        assertEquals(setOf("root"), rootfs.list()!!.toSet())
        assertFalse(File(rootfs, "root/.dsh").exists())
        assertFalse(File(rootfs, "sdcard/Download").exists())
        assertFalse(File(rootfs, "opt").exists())
        assertEquals(setOf("README.md"), directory.walkTopDown().filter { it.isFile }.map { it.name }.toSet())
    }

    @Test fun preparationIsIdempotentAndPreservesExistingDownloadsBuildsAndReadmeIdentity() {
        val rootfs = temp.newFolder("rootfs")
        val directory = GuestDependencies.prepare(rootfs)
        val archive = seed(directory, "downloads/archive.tgz", byteArrayOf(0, 1, 2, -1))
        val output = seed(directory, "build/result.bin", byteArrayOf(4, 5, 6))
        val cache = seed(directory, "cache/npm/custom-cache")
        val readme = File(directory, "README.md")
        assertTrue(readme.setLastModified(1_500_000_000_000L))
        val original = readme.readBytes(); val modified = readme.lastModified()
        val key = Files.readAttributes(readme.toPath(), java.nio.file.attribute.BasicFileAttributes::class.java).fileKey()
        repeat(2) { assertEquals(directory, GuestDependencies.prepare(rootfs)) }
        assertArrayEquals(original, readme.readBytes()); assertEquals(modified, readme.lastModified())
        assertEquals(key, Files.readAttributes(readme.toPath(), java.nio.file.attribute.BasicFileAttributes::class.java).fileKey())
        assertArrayEquals(byteArrayOf(0, 1, 2, -1), archive.readBytes())
        assertArrayEquals(byteArrayOf(4, 5, 6), output.readBytes())
        assertEquals("keep\n", cache.readText())
        assertFalse(directory.list()!!.any { it.startsWith(".dependencies-readme-") })
    }

    @Test fun userOwnedReadmeKeepsItsExactBytesIncludingMalformedUtf8() {
        val rootfs = temp.newFolder("rootfs")
        val bytes = byteArrayOf(0xc3.toByte(), 0x28, 0, 0xff.toByte())
        val readme = seed(rootfs, "$relativeRoot/README.md", bytes)
        assertTrue(readme.setLastModified(1_500_000_000_000L))
        val modified = readme.lastModified()
        repeat(2) { GuestDependencies.prepare(rootfs) }
        assertArrayEquals(bytes, readme.readBytes()); assertEquals(modified, readme.lastModified())
        assertTrue(File(dependencyRoot(rootfs), "cache/node-gyp").isDirectory)
    }

    @Test fun onlyTheUniqueDependencyMarkerGrantsManagedReadmeReplacement() {
        val rootfs = temp.newFolder("rootfs")
        val old = "<!-- deepseek-harness:managed-dependencies-v1 -->\nold instructions\n"
        val readme = seed(rootfs, "$relativeRoot/README.md", old.toByteArray())
        GuestDependencies.prepare(rootfs)
        val text = readme.readText()
        assertNotEquals(old, text)
        assertEquals(1, Regex(Regex.escape("<!-- deepseek-harness:managed-dependencies-v1 -->")).findAll(text).count())
        assertTrue(text.contains(GuestDependencies.instructions()))
        readme.writeText("<!-- dsh-app:managed -->\nuser-owned dependency notes\n")
        val bytes = readme.readBytes()
        GuestDependencies.prepare(rootfs)
        assertArrayEquals(bytes, readme.readBytes())
    }

    @Test fun readmeBodyReferencesAndMarkerWithoutFirstLineTerminatorRemainUserOwned() {
        for (text in listOf("# User notes\n<!-- deepseek-harness:managed-dependencies-v1 -->\nquoted example\n",
            "<!-- deepseek-harness:managed-dependencies-v1 --> is quoted, not a managed first line\n")) {
            val rootfs = temp.newFolder()
            val readme = seed(rootfs, "$relativeRoot/README.md", text.toByteArray())
            GuestDependencies.prepare(rootfs)
            assertArrayEquals(text.toByteArray(), readme.readBytes())
        }
    }

    @Test fun oversizedReadmeIsPreservedEvenWhenItStartsWithTheManagedMarker() {
        for (managed in listOf(false, true)) {
            val rootfs = temp.newFolder()
            val bytes = ByteArray(64 * 1024 + 1) { 65 }
            if (managed) "<!-- deepseek-harness:managed-dependencies-v1 -->\n".toByteArray().copyInto(bytes)
            val readme = seed(rootfs, "$relativeRoot/README.md", bytes)
            assertTrue(readme.setLastModified(1_500_000_000_000L))
            val modified = readme.lastModified()
            GuestDependencies.prepare(rootfs)
            assertArrayEquals(bytes, readme.readBytes()); assertEquals(modified, readme.lastModified())
        }
        val rootfs = temp.newFolder()
        val bytes = ByteArray(64 * 1024) { 65 }
        "<!-- deepseek-harness:managed-dependencies-v1 -->\n".toByteArray().copyInto(bytes)
        val readme = seed(rootfs, "$relativeRoot/README.md", bytes)
        GuestDependencies.prepare(rootfs)
        assertTrue(readme.length() < 64 * 1024)
        assertTrue(readme.readText().contains("## 依赖下载、安装与编译目录"))
    }

    @Test fun oldDependencyLocationsAreNotMigratedOrReset() {
        val rootfs = temp.newFolder("rootfs")
        val oldPaths = listOf("root/.npm/data", "root/.cache/pip/data", "root/.cargo/data", "root/.rustup/data",
            "root/go/data", "root/.dsh/dependencies/data", "root/workspace/node_modules/package/data",
            "sdcard/Download/DSH/data")
        val oldFiles = oldPaths.map { seed(rootfs, it, it.toByteArray()) }
        GuestDependencies.prepare(rootfs)
        for ((index, file) in oldFiles.withIndex()) assertArrayEquals(oldPaths[index].toByteArray(), file.readBytes())
        assertEquals(setOf("README.md"), dependencyRoot(rootfs).walkTopDown().filter { it.isFile }.map { it.name }.toSet())
    }

    @Test fun preparationDoesNotChangeExistingPosixModes() {
        val rootfs = temp.newFolder("rootfs")
        assumeTrue("POSIX modes require a POSIX filesystem", Files.getFileStore(rootfs.toPath()).supportsFileAttributeView("posix"))
        val directory = GuestDependencies.prepare(rootfs)
        val executable = seed(directory, "bin/tool")
        val readme = File(directory, "README.md")
        val ownerOnly = PosixFilePermissions.fromString("rwx------")
        val fileMode = PosixFilePermissions.fromString("r-x------")
        Files.setPosixFilePermissions(File(directory, "npm").toPath(), ownerOnly)
        Files.setPosixFilePermissions(executable.toPath(), fileMode)
        Files.setPosixFilePermissions(readme.toPath(), PosixFilePermissions.fromString("r--------"))
        GuestDependencies.prepare(rootfs)
        assertEquals(ownerOnly, Files.getPosixFilePermissions(File(directory, "npm").toPath()))
        assertEquals(fileMode, Files.getPosixFilePermissions(executable.toPath()))
        assertEquals(PosixFilePermissions.fromString("r--------"), Files.getPosixFilePermissions(readme.toPath()))
    }

    @Test fun rejectsMissingRootfsAndRegularFileRootfsWithoutCreatingThem() {
        val missing = File(temp.root, "missing-rootfs")
        expectPathFailure { GuestDependencies.prepare(missing) }
        assertFalse(missing.exists())
        val file = temp.newFile("rootfs-file").apply { writeText("keep") }
        expectPathFailure { GuestDependencies.prepare(file) }
        assertEquals("keep", file.readText())
    }

    @Test fun rejectsRegularFileCollisionsAtEveryDirectoryLevel() {
        for (relative in listOf("root", "root/.local", "root/.local/share", "root/.local/share/deepseek-harness",
            relativeRoot, "$relativeRoot/bin", "$relativeRoot/npm/bin", "$relativeRoot/cache", "$relativeRoot/cache/node-gyp")) {
            val rootfs = temp.newFolder()
            val file = seed(rootfs, relative)
            expectPathFailure { GuestDependencies.prepare(rootfs) }
            assertEquals("keep\n", file.readText())
        }
    }

    @Test fun rejectsDirectoryReadmeCollisionWithoutRemovingIt() {
        val rootfs = temp.newFolder("rootfs")
        val readme = File(rootfs, "$relativeRoot/README.md").apply { mkdirs() }
        val child = seed(readme, "user-file")
        expectPathFailure { GuestDependencies.prepare(rootfs) }
        assertEquals("keep\n", child.readText())
    }

    @Test fun rejectsLinkedRootfsAndDirectRuntimeParentBeforeWritingOutside() {
        val outside = temp.newFolder("outside")
        val physicalRoot = File(outside, "physical-rootfs").apply { mkdirs() }
        val rootLink = File(temp.root, "root-link")
        Files.createSymbolicLink(rootLink.toPath(), physicalRoot.toPath())
        expectPathFailure { GuestDependencies.prepare(rootLink) }
        val runtimeLink = File(temp.root, "runtime-link")
        Files.createSymbolicLink(runtimeLink.toPath(), outside.toPath())
        expectPathFailure { GuestDependencies.prepare(File(runtimeLink, "physical-rootfs")) }
        assertEquals(emptyList<String>(), physicalRoot.list()!!.toList())
    }

    @Test fun trustedSystemAliasAboveTheRealRuntimeParentIsSupported() {
        val storage = temp.newFolder("system-storage")
        val physicalRoot = File(storage, "runtime/rootfs").apply { mkdirs() }
        val alias = File(temp.root, "trusted-storage-alias")
        Files.createSymbolicLink(alias.toPath(), storage.toPath())
        val aliasedRoot = File(alias, "runtime/rootfs")
        assertEquals(dependencyRoot(aliasedRoot), GuestDependencies.prepare(aliasedRoot))
        assertTrue(File(dependencyRoot(physicalRoot), "README.md").isFile)
        assertTrue(Files.isSymbolicLink(alias.toPath()))
    }

    @Test fun rejectsLinkedDependencyComponentsIncludingLinksBackInsideTheRootfs() {
        for (relative in listOf("root", "root/.local", "root/.local/share", "root/.local/share/deepseek-harness",
            relativeRoot, "$relativeRoot/bin", "$relativeRoot/npm/bin", "$relativeRoot/cache/pip")) {
            val rootfs = temp.newFolder()
            val outside = temp.newFolder()
            val link = File(rootfs, relative).apply { parentFile.mkdirs() }
            Files.createSymbolicLink(link.toPath(), outside.toPath())
            expectPathFailure { GuestDependencies.prepare(rootfs) }
            assertEquals(emptyList<String>(), outside.list()!!.toList())
        }
        val rootfs = temp.newFolder(); val inside = File(rootfs, "inside").apply { mkdirs() }
        Files.createSymbolicLink(File(rootfs, "root").toPath(), inside.toPath())
        expectPathFailure { GuestDependencies.prepare(rootfs) }
        assertEquals(emptyList<String>(), inside.list()!!.toList())
    }

    @Test fun rejectsLinkedAndDanglingReadmesWithoutTouchingTheirTargets() {
        for (exists in listOf(true, false)) {
            val rootfs = temp.newFolder()
            val outside = File(temp.root, "readme-target-$exists")
            if (exists) outside.writeText("keep target")
            val readme = File(rootfs, "$relativeRoot/README.md").apply { parentFile.mkdirs() }
            Files.createSymbolicLink(readme.toPath(), outside.toPath())
            expectPathFailure { GuestDependencies.prepare(rootfs) }
            assertTrue(Files.isSymbolicLink(readme.toPath()))
            if (exists) assertEquals("keep target", outside.readText()) else assertFalse(outside.exists())
        }
    }

    @Test fun environmentHasExactContractPathsWithoutAddingSystemOverrideVariables() {
        val env = GuestDependencies.environment(emptyMap(), "/opt/node/bin:/usr/local/bin:/usr/bin:/bin")
        assertEquals("/root/.local/share/deepseek-harness/dependencies", env["DSH_DEPENDENCY_ROOT"])
        assertEquals("/root/.local/share/deepseek-harness/dependencies/npm", env["NPM_CONFIG_PREFIX"])
        assertEquals("/root/.local/share/deepseek-harness/dependencies/cache/npm", env["NPM_CONFIG_CACHE"])
        assertEquals("/root/.local/share/deepseek-harness/dependencies/cache/node-gyp", env["NPM_CONFIG_DEVDIR"])
        assertEquals("/root/.local/share/deepseek-harness/dependencies/python", env["PYTHONUSERBASE"])
        assertEquals("/root/.local/share/deepseek-harness/dependencies/cache/pip", env["PIP_CACHE_DIR"])
        assertEquals("/root/.local/share/deepseek-harness/dependencies/cargo", env["CARGO_HOME"])
        assertEquals("/root/.local/share/deepseek-harness/dependencies/rustup", env["RUSTUP_HOME"])
        assertEquals("/root/.local/share/deepseek-harness/dependencies/go", env["GOPATH"])
        assertEquals("/root/.local/share/deepseek-harness/dependencies/cache/go-mod", env["GOMODCACHE"])
        assertEquals("/root/.local/share/deepseek-harness/dependencies/cache/go-build", env["GOCACHE"])
        assertEquals("/root/.local/share/deepseek-harness/dependencies/cache/ccache", env["CCACHE_DIR"])
        assertEquals("/root/.local/share/deepseek-harness/dependencies/tmp", env["TMPDIR"])
        assertEquals(14, env.size)
        for (key in listOf("HOME", "DSH_HOME", "PROOT_TMP_DIR", "LD_LIBRARY_PATH", "PIP_TARGET", "PIP_PREFIX", "PIP_USER")) {
            assertFalse(key, env.containsKey(key))
        }
    }

    @Test fun environmentDoesNotMutateLegacyValuesPrivilegedOrSecretFields() {
        val base = linkedMapOf("HOME" to "/root", "DSH_HOME" to "/var/lib/dsh-app/safe-mode/home",
            "PROOT_TMP_DIR" to "/host/proot-tmp", "PROOT_LOADER" to "/host/loader", "LD_LIBRARY_PATH" to "/user/lib",
            "PIP_TARGET" to "/project/vendor", "PIP_PREFIX" to "/user/python", "PIP_USER" to "false",
            "OPENAI_API_KEY" to "synthetic-secret", "DSH_TOKEN" to "synthetic-token", "CUSTOM" to "keep",
            "npm_config_registry" to "https://registry.example.test", "DSH_DEPENDENCY_ROOT" to "/legacy/dependencies",
            "NPM_CONFIG_CACHE" to "/legacy/npm", "TMPDIR" to "/host/tmp", "PATH" to "/opt/node/bin:/usr/bin")
        val original = LinkedHashMap(base)
        val env = GuestDependencies.environment(base, "/ignored")
        assertNotSame(base, env); assertEquals(original, base)
        for (key in original.keys - setOf("DSH_DEPENDENCY_ROOT", "NPM_CONFIG_CACHE", "TMPDIR", "PATH")) {
            assertEquals(key, original[key], env[key])
        }
        assertEquals("/legacy/dependencies", base["DSH_DEPENDENCY_ROOT"])
        assertEquals("/host/tmp", base["TMPDIR"])
        assertEquals("/root/.local/share/deepseek-harness/dependencies", env["DSH_DEPENDENCY_ROOT"])
        assertEquals("/root/.local/share/deepseek-harness/dependencies/tmp", env["TMPDIR"])
    }

    @Test fun managedVariableCaseDuplicatesAreRemovedWithoutRemovingOtherNpmOptions() {
        val base = linkedMapOf("npm_config_prefix" to "/shadow", "Npm_Config_Prefix" to "/shadow2", "NPM_CONFIG_PREFIX" to "/old",
            "npm_config_cache" to "/cache", "Npm_Config_Devdir" to "/headers", "pythonuserbase" to "/python",
            "pip_cache_dir" to "/pip", "cargo_home" to "/cargo", "rustup_home" to "/rustup", "gopath" to "/go",
            "gomodcache" to "/mod", "gocache" to "/build", "ccache_dir" to "/ccache", "tmpdir" to "/tmp",
            "dsh_dependency_root" to "/legacy", "npm_config_registry" to "keep", "Path" to "/user/bin")
        val original = LinkedHashMap(base)
        val env = GuestDependencies.environment(base, "/fallback")
        for (key in base.keys - setOf("npm_config_registry", "NPM_CONFIG_PREFIX")) assertFalse(key, env.containsKey(key))
        assertEquals("keep", env["npm_config_registry"]); assertEquals(original, base)
        assertEquals(1, env.keys.count { it.equals("NPM_CONFIG_PREFIX", ignoreCase = true) })
        assertTrue(env["PATH"]!!.startsWith("/user/bin:"))
    }

    @Test fun pathPreservesOfficialAndUserOrderAndDeduplicatesOnlyLaterOccurrences() {
        val prefix = "/opt/node/bin:/usr/local/bin:/usr/bin:/bin:/custom/bin:/root/.local/share/deepseek-harness/dependencies/npm/bin"
        val base = mapOf("PATH" to "$prefix:/usr/bin::/custom/bin")
        val expected = "$prefix::/root/.local/share/deepseek-harness/dependencies/bin:" +
            "/root/.local/share/deepseek-harness/dependencies/python/bin:" +
            "/root/.local/share/deepseek-harness/dependencies/cargo/bin:" +
            "/root/.local/share/deepseek-harness/dependencies/go/bin"
        assertEquals(expected, GuestDependencies.environment(base, "/ignored")["PATH"])
        val env = GuestDependencies.environment(base, "/ignored")
        assertEquals(env, GuestDependencies.environment(env, "/different"))
    }

    @Test fun pathUsesDefaultOnlyWhenAbsentAndKeepsExplicitEmptyEntries() {
        val bins = "/root/.local/share/deepseek-harness/dependencies/bin:" +
            "/root/.local/share/deepseek-harness/dependencies/npm/bin:" +
            "/root/.local/share/deepseek-harness/dependencies/python/bin:" +
            "/root/.local/share/deepseek-harness/dependencies/cargo/bin:" +
            "/root/.local/share/deepseek-harness/dependencies/go/bin"
        assertEquals("/opt/node/bin:/usr/bin:$bins", GuestDependencies.environment(emptyMap(), "/opt/node/bin:/usr/bin")["PATH"])
        assertEquals(":$bins", GuestDependencies.environment(mapOf("PATH" to ""), "/fallback")["PATH"])
        assertEquals("/exact:$bins", GuestDependencies.environment(linkedMapOf("Path" to "/shadow", "PATH" to "/exact"), "/fallback")["PATH"])
    }

    @Test fun instructionsExplainVenvProjectAndSystemContractsAndDataLifetime() {
        val text = GuestDependencies.instructions()
        for (expected in listOf("/root/.local/share/deepseek-harness/dependencies", "${'$'}DSH_DEPENDENCY_ROOT/downloads",
            "${'$'}DSH_DEPENDENCY_ROOT/sources", "${'$'}DSH_DEPENDENCY_ROOT/build", "${'$'}DSH_DEPENDENCY_ROOT/cache",
            "${'$'}DSH_DEPENDENCY_ROOT/tmp", "python3 -m venv", "venvs/NAME", "pip install --user", "node_modules",
            "Ubuntu 系统包管理器", "不强制覆盖系统 Python", "不自动搬移", "15 项固定替换路径之外", "卸载 App", "清除 App 数据")) {
            assertTrue(expected, text.contains(expected))
        }
        assertFalse(text.contains("--break-system-packages"))
        assertFalse(text.contains("PIP_TARGET="))
        assertFalse(text.contains("LD_LIBRARY_PATH="))
        assertFalse(text.contains("PROOT_TMP_DIR="))
        assertFalse(text.contains("\\${'$'}DSH_"))
    }
}
