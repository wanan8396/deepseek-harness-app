package app.dsh.runtime

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.io.IOException
import java.nio.file.Files

class OfficialPhoneSkillsTest {
    private val guideName = "deepseek-harness-guide"
    private val skill = "---\n# deepseek-harness:managed\nname: deepseek-harness-guide\ndescription: DeepSeek harness phone guide\n---\n# DeepSeek harness\n"
    private val prefix = "flutter_assets/assets/skills/dsh-app-guide/"
    private fun assets(path: String): String = when (path) {
        prefix + "manifest.json" -> """{"name":"deepseek-harness-guide","files":{"SKILL.md":"SKILL.md","README.md":"zh/help.md"}}"""
        prefix + "SKILL.md" -> skill
        prefix + "README.md" -> "DeepSeek harness help\n"
        else -> error("unexpected asset")
    }
    private fun dir(root: File) = File(root, "root/.dsh/skills/$guideName")
    private fun put(root: File, text: String = skill): File = File(dir(root), "SKILL.md").apply {
        parentFile!!.mkdirs(); writeText(text)
    }
    private inline fun withRoot(block: (File) -> Unit) {
        val root = Files.createTempDirectory("official-phone-skills").toFile()
        try { block(root) } finally { root.deleteRecursively() }
    }

    @Test fun freshHomeGetsCurrentGuideBeforeFirstEngineStart() = withRoot { root ->
        val result = OfficialPhoneSkills.sync(root, ::assets) { true }
        assertEquals("installed", result.guide)
        assertEquals(skill, File(dir(root), "SKILL.md").readText())
        assertEquals("DeepSeek harness help\n", File(dir(root), "zh/help.md").readText())
    }

    @Test fun managedGuideUpdatesOnlyItsBundleAndRerunIsIdempotent() = withRoot { root ->
        val guide = put(root, skill + "outdated")
        val custom = File(dir(root), "my-extra.txt").apply { writeText("mine") }
        val unrelated = File(root, "root/.dsh/skills/personal/SKILL.md").apply {
            parentFile!!.mkdirs(); writeText("personal skill")
        }
        val profile = File(root, "root/.dsh/profiles/web/cordis.patch.yml").apply {
            parentFile!!.mkdirs(); writeText("keep my settings")
        }
        val result = OfficialPhoneSkills.sync(root, ::assets) { true }
        assertEquals("updated", result.guide)
        assertEquals(skill, guide.readText())
        assertEquals("mine", custom.readText())
        assertEquals("personal skill", unrelated.readText())
        assertEquals("keep my settings", profile.readText())
        val modified = guide.lastModified()
        assertEquals("unchanged", OfficialPhoneSkills.sync(root, ::assets) { true }.guide)
        assertEquals(modified, guide.lastModified())
    }

    @Test fun userOwnedGuideAndMarkerOutsideFrontmatterStayByteIdentical() = withRoot { root ->
        val guide = put(root, "---\nname: personal\n---\n# deepseek-harness:managed\nmy guide")
        val bytes = guide.readBytes()
        assertEquals("userOwned", OfficialPhoneSkills.sync(root, ::assets) { true }.guide)
        assertArrayEquals(bytes, guide.readBytes())
        assertFalse(File(dir(root), "zh/help.md").exists())
    }

    @Test fun guideNeverFollowsDirectorySymlinksEvenWithinTheRuntime() = withRoot { root ->
        val personal = File(root, "personal").apply { mkdirs() }
        val original = File(personal, "SKILL.md").apply { writeText(skill) }
        val skills = File(root, "root/.dsh/skills").apply { mkdirs() }
        Files.createSymbolicLink(File(skills, guideName).toPath(), personal.toPath())
        assertEquals("userOwned", OfficialPhoneSkills.sync(root, ::assets) { true }.guide)
        assertEquals(skill, original.readText())
        assertFalse(File(personal, "zh").exists())
    }

    @Test fun guideNeverFollowsFileOrStagingSymlinks() = withRoot { root ->
        for (name in listOf("zh/help.md", "zh/help.md.deepseek-harness-tmp")) {
            val target = File(root, "personal.txt").apply { writeText("mine") }
            val alias = File(dir(root), name).apply { parentFile!!.mkdirs() }
            Files.createSymbolicLink(alias.toPath(), target.toPath())
            assertEquals("userOwned", OfficialPhoneSkills.sync(root, ::assets) { true }.guide)
            assertEquals("mine", target.readText())
            assertFalse(File(dir(root), "SKILL.md").exists())
            Files.delete(alias.toPath())
        }
    }

    @Test fun cancellationBeforeSyncWritesNothing() = withRoot { root ->
        try { OfficialPhoneSkills.sync(root, ::assets) { false }; fail("expected cancellation") }
        catch (failure: IOException) { assertEquals("official_phone_skills_cancelled", failure.message) }
        assertFalse(File(root, "root").exists())
    }

    @Test fun cancellationAfterStagingLeavesSkillUnpublishedAndRetryFinishes() = withRoot { root ->
        val staged = File(dir(root), "zh/help.md.deepseek-harness-tmp")
        try {
            OfficialPhoneSkills.sync(root, ::assets) { !staged.exists() }
            fail("expected cancellation")
        } catch (failure: IOException) { assertEquals("official_phone_skills_cancelled", failure.message) }
        assertFalse(File(dir(root), "SKILL.md").exists())
        assertFalse(staged.exists())
        assertEquals("installed", OfficialPhoneSkills.sync(root, ::assets) { true }.guide)
        assertEquals("unchanged", OfficialPhoneSkills.sync(root, ::assets) { true }.guide)
    }

    @Test fun manifestIdentityMustMatchCurrentGuide() = withRoot { root ->
        try {
            OfficialPhoneSkills.sync(root, { path ->
                if (path == prefix + "manifest.json")
                    """{"name":"personal-guide","files":{"SKILL.md":"SKILL.md"}}"""
                else assets(path)
            }) { true }
            fail("expected invalid bundle")
        } catch (failure: IOException) { assertEquals("official_phone_skills_io", failure.message) }
        assertFalse(File(root, "root").exists())
    }

    @Test fun actualBundledGuideInstallsEveryGeneratedFileWithCurrentIdentityAndRootInstructions() = withRoot { root ->
        val app = listOfNotNull(System.getProperty("phase2.app"), "../..", ".").map(::File)
            .first { File(it, "assets/skills/dsh-app-guide").isDirectory }
        val assets = File(app, "assets/skills/dsh-app-guide")
        val result = OfficialPhoneSkills.sync(root, { path -> File(assets, path.removePrefix(prefix)).readText() }) { true }
        assertEquals("installed", result.guide)
        val bundle = JSONObject(File(assets, "manifest.json").readText())
        assertEquals(guideName, bundle.getString("name"))
        val manifest = bundle.getJSONObject("files")
        assertEquals(26, manifest.length())
        for (name in manifest.keys()) {
            assertArrayEquals(File(assets, name).readBytes(), File(dir(root), manifest.getString(name)).readBytes())
        }
        val entry = File(dir(root), "SKILL.md").readText()
        assertTrue(entry.contains("# deepseek-harness:managed"))
        assertTrue(entry.contains("name: deepseek-harness-guide"))
        assertTrue(File(dir(root), "zh/04-permissions.md").readText().contains("恢复模式跳过 Root 探测"))
        assertTrue(File(dir(root), "en/04-permissions.md").readText().contains("Recovery mode skips the Root probe"))
        for (locale in listOf("zh", "en")) {
            for (name in listOf("04-permissions.md", "06-navigation.md", "12-automation.md", "07-sharing.md", "08-plugins.md")) {
                assertTrue("Missing $locale/$name", File(dir(root), "$locale/$name").isFile)
            }
        }
    }
}
