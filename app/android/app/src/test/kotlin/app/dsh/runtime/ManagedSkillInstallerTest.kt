package app.dsh.runtime

import org.json.JSONObject
import java.io.File
import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Test

class ManagedSkillInstallerTest {
    private val skill = "---\n# deepseek-harness:managed\nname: deepseek-harness-guide\n---\n中文 🐳\n"
    private fun files(value: String = "value") = linkedMapOf("SKILL.md" to skill, "nested/data.txt" to value)
    private fun root() = Files.createTempDirectory("managed-skill-").toFile().apply { File(this, "root/.dsh").mkdirs() }
    private fun request(root: File, files: Map<String, String> = files(), name: String = "deepseek-harness-guide") =
        ManagedSkillRequest.create(root.path, name, files)!!
    private fun dir(root: File, name: String = "deepseek-harness-guide") = File(root, "root/.dsh/skills/$name")
    private fun noTemps(root: File) = assertFalse(root.walkTopDown().any { it.name.endsWith(".deepseek-harness-tmp") })
    private inline fun withRoot(test: (File) -> Unit) { val root = root(); try { test(root) } finally { root.deleteRecursively() } }

    @Test fun typedGuideInputsAreSnapshottedBeforeInstallation() = withRoot { root ->
        val input = files()
        val request = ManagedSkillRequest.create(root.path, "deepseek-harness-guide", input)!!
        assertEquals(root.path, request.expectedRoot)
        assertEquals("deepseek-harness-guide", request.name)
        input["SKILL.md"] = "changed"
        input["nested/data.txt"] = "changed"
        input["injected.txt"] = "extra"
        assertEquals(mapOf("SKILL.md" to skill, "nested/data.txt" to "value"), request.files)
        assertEquals("installed", ManagedSkillInstaller.install(root, request) { true }.result)
        assertArrayEquals(skill.toByteArray(), File(dir(root), "SKILL.md").readBytes())
        assertEquals("value", File(dir(root), "nested/data.txt").readText())
        assertFalse(File(dir(root), "injected.txt").exists())
        noTemps(root)
    }

    @Test fun firstInstallWritesExactUtf8AndCurrentInstallDoesNotWrite() = withRoot { root ->
        val request = request(root)
        assertEquals("installed", ManagedSkillInstaller.install(root, request) { true }.result)
        for ((path, text) in request.files) assertArrayEquals(text.toByteArray(), File(dir(root), path).readBytes())
        val times = request.files.keys.associateWith { File(dir(root), it).lastModified() }
        assertEquals("unchanged", ManagedSkillInstaller.install(root, request) { true }.result)
        for ((path, time) in times) assertEquals(time, File(dir(root), path).lastModified())
        noTemps(root)
    }

    @Test fun actualGuideBundleFitsBudgetAndMatchesEveryByte() = withRoot { root ->
        // Gradle runs unit tests in app/android/app; the Flutter app (and its
        // assets/) is two levels up. phase2.app still overrides it.
        val app = listOfNotNull(System.getProperty("phase2.app"), "../..", ".")
            .map(::File)
            .first { File(it, "assets/skills/dsh-app-guide").isDirectory }
        val assets = File(app, "assets/skills/dsh-app-guide")
        val manifest = JSONObject(File(assets, "manifest.json").readText())
        assertEquals("deepseek-harness-guide", manifest.getString("name"))
        val entries = manifest.getJSONObject("files")
        val bundled = entries.keys().asSequence().associate { asset ->
            entries.getString(asset) to File(assets, asset).readText()
        }
        assertEquals("installed", ManagedSkillInstaller.install(root, request(root, files = bundled)) { true }.result)
        for ((path, text) in bundled) {
            assertArrayEquals(text.toByteArray(), File(dir(root), path).readBytes())
        }
        assertTrue(bundled.isNotEmpty())
        assertTrue(bundled.values.sumOf { it.toByteArray().size } > 0)
        noTemps(root)
    }

    @Test fun repairsOnlyChangedOrMissingManagedFiles() = withRoot { root ->
        val request = request(root)
        ManagedSkillInstaller.install(root, request) { true }
        val skillFile = File(dir(root), "SKILL.md")
        val modified = skillFile.lastModified()
        File(dir(root), "nested/data.txt").writeText("broken")
        assertEquals("updated", ManagedSkillInstaller.install(root, request) { true }.result)
        assertEquals(modified, skillFile.lastModified())
        File(dir(root), "nested/data.txt").delete()
        assertEquals("updated", ManagedSkillInstaller.install(root, request) { true }.result)
        assertEquals("value", File(dir(root), "nested/data.txt").readText())
    }

    @Test fun removedMarkerLeavesEveryUserFileAlone() = withRoot { root ->
        ManagedSkillInstaller.install(root, request(root)) { true }
        File(dir(root), "SKILL.md").writeText(skill.replace("# deepseek-harness:managed", "# user-owned"))
        File(dir(root), "nested/data.txt").writeText("mine")
        assertEquals("userOwned", ManagedSkillInstaller.install(root, request(root)) { true }.result)
        assertEquals("mine", File(dir(root), "nested/data.txt").readText())
    }

    @Test fun markerOutsideFrontmatterDoesNotAuthorizeOverwrite() = withRoot { root ->
        File(dir(root), "SKILL.md").apply { parentFile!!.mkdirs(); writeText("---\nname: mine\n---\n# deepseek-harness:managed\n") }
        assertEquals("userOwned", ManagedSkillInstaller.install(root, request(root)) { true }.result)
        assertFalse(File(dir(root), "nested").exists())
    }

    @Test fun malformedExistingSkillIsUserOwnedAndBomMatchesDart() = withRoot { root ->
        val file = File(dir(root), "SKILL.md").apply { parentFile!!.mkdirs(); writeBytes(byteArrayOf(0xc3.toByte(), 0x28)) }
        assertEquals("userOwned", ManagedSkillInstaller.install(root, request(root)) { true }.result)
        file.writeText("\uFEFF$skill")
        File(dir(root), "nested/data.txt").apply { parentFile!!.mkdirs(); writeText("\uFEFFvalue") }
        assertEquals("unchanged", ManagedSkillInstaller.install(root, request(root)) { true }.result)
        assertTrue(file.readText().startsWith("\uFEFF"))
    }

    @Test fun absentDshHomeCreatesNothing() = withRoot { root ->
        File(root, "root").deleteRecursively()
        assertEquals("noHome", ManagedSkillInstaller.install(root, request(root)) { true }.result)
        assertFalse(File(root, "root").exists())
    }

    @Test fun wrongRootAndRetiredAdmissionCreateNothing() = withRoot { root ->
        val wrong = ManagedSkillRequest.create(File(root, "other").path, "deepseek-harness-guide", files())!!
        assertEquals("stale", ManagedSkillInstaller.install(root, wrong) { true }.reason)
        assertEquals("cancelled", ManagedSkillInstaller.install(root, request(root)) { false }.reason)
        assertFalse(dir(root).exists())
    }

    @Test fun pathAliasesToSameRootAreAcceptedOnlyAfterWorkerCanonicalCheck() = withRoot { root ->
        val alias = ManagedSkillRequest.create(root.path + "/./", "deepseek-harness-guide", files())!!
        assertEquals("installed", ManagedSkillInstaller.install(root, alias) { true }.result)
    }

    @Test fun safeNamesAndPayloadBudgetsRejectTheEntireRequest() = withRoot { root ->
        for (bad in listOf("../data", "/data", "a/../../data", "a//b", "a/./b", "a\\b", "a".repeat(513))) {
            assertNull(ManagedSkillRequest.create(root.path, "deepseek-harness-guide", files() + (bad to "bad")))
        }
        for (name in listOf("other", "personal-guide", "deepseek-harness-guide-copy")) {
            assertNull(ManagedSkillRequest.create(root.path, name, files()))
        }
        assertNull(ManagedSkillRequest.create(root.path, "deepseek-harness-guide", emptyMap()))
        assertNull(ManagedSkillRequest.create(root.path, "deepseek-harness-guide", mapOf("data" to "no skill")))
        assertNull(ManagedSkillRequest.create(root.path, "deepseek-harness-guide", files() + ("big" to "x".repeat(524289))))
        assertNull(ManagedSkillRequest.create(root.path, "deepseek-harness-guide", (0..63).associate { "f$it" to "x" } + ("SKILL.md" to skill)))
        assertFalse(dir(root).exists())
    }

    @Test fun rootAndBundleCharacterLimitsKeepTheirExactBoundaries() = withRoot { root ->
        assertNull(ManagedSkillRequest.create("", "deepseek-harness-guide", files()))
        assertNull(ManagedSkillRequest.create("r".repeat(4097), "deepseek-harness-guide", files()))
        assertNotNull(ManagedSkillRequest.create("r".repeat(4096), "deepseek-harness-guide", files()))
        assertNotNull(ManagedSkillRequest.create(root.path, "deepseek-harness-guide", files() + ("a".repeat(512) to "value")))
        assertNotNull(ManagedSkillRequest.create(root.path, "deepseek-harness-guide", (0..62).associate { "f$it" to "x" } + ("SKILL.md" to skill)))
        val atLimit = linkedMapOf("SKILL.md" to skill, "large" to "x".repeat(524288),
            "other" to "y".repeat(524288 - skill.length))
        assertNotNull(ManagedSkillRequest.create(root.path, "deepseek-harness-guide", atLimit))
        assertNull(ManagedSkillRequest.create(root.path, "deepseek-harness-guide", atLimit + ("overflow" to "x")))
        assertFalse(dir(root).exists())
    }

    @Test fun utf8BudgetIsCheckedBeforeAnyFileIsCreated() = withRoot { root ->
        val huge = request(root, files = files() + ("large" to "中".repeat(200000)))
        assertEquals("invalid", ManagedSkillInstaller.install(root, huge) { true }.reason)
        assertFalse(dir(root).exists())
    }

    @Test fun totalUtf8BudgetIsCheckedAcrossIndividuallyValidFiles() = withRoot { root ->
        val text = "中".repeat(120000)
        val huge = request(root, files = files() + mapOf("one" to text, "two" to text, "three" to text))
        assertEquals("invalid", ManagedSkillInstaller.install(root, huge) { true }.reason)
        assertFalse(dir(root).exists())
    }

    @Test fun malformedUtf16InputStopsBeforeAnyFileIsCreated() = withRoot { root ->
        val malformed = request(root, files = files("\uD800"))
        assertEquals("io", ManagedSkillInstaller.install(root, malformed) { true }.reason)
        assertFalse(dir(root).exists())
    }

    @Test fun escapedFileSymlinkIsNotFollowed() = withRoot { root ->
        val outside = Files.createTempFile("managed-outside-", ".txt").toFile()
        try {
            outside.writeText("mine")
            File(dir(root), "nested").mkdirs()
            Files.createSymbolicLink(File(dir(root), "nested/data.txt").toPath(), outside.toPath())
            assertEquals("userOwned", ManagedSkillInstaller.install(root, request(root)) { true }.result)
            assertEquals("mine", outside.readText())
        } finally { outside.delete() }
    }

    @Test fun cancellationAfterStagingStopsRenameAndSkillIsLast() = withRoot { root ->
        val staged = File(dir(root), "nested/data.txt.deepseek-harness-tmp")
        val result = ManagedSkillInstaller.install(root, request(root)) { !staged.exists() }
        assertEquals("cancelled", result.reason)
        assertFalse(File(dir(root), "nested/data.txt").exists())
        assertFalse(File(dir(root), "SKILL.md").exists())
        noTemps(root)
        var sawOther = false
        assertEquals("installed", ManagedSkillInstaller.install(root, request(root)) {
            if (File(dir(root), "SKILL.md.deepseek-harness-tmp").exists()) {
                sawOther = File(dir(root), "nested/data.txt").readText() == "value"
            }
            true
        }.result)
        assertTrue(sawOther)
    }

    @Test fun failureLeavesSkillUnpublishedAndNextRunRepairs() = withRoot { root ->
        File(dir(root), "nested").apply { parentFile!!.mkdirs(); writeText("not a directory") }
        assertEquals("io", ManagedSkillInstaller.install(root, request(root)) { true }.reason)
        assertFalse(File(dir(root), "SKILL.md").exists())
        File(dir(root), "nested").delete()
        assertEquals("installed", ManagedSkillInstaller.install(root, request(root)) { true }.result)
        noTemps(root)
    }
}
