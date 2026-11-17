package app.dsh.runtime

import java.io.File
import org.junit.Assert.*
import org.junit.Test

class LocalWebLiteGuestTest {
    @Test fun managedHistoricalInstructionsAreReplacedByTheOfficialWebContract() {
        val root = kotlin.io.path.createTempDirectory("lite-guest").toFile()
        try {
            val file = File(root, "root/.dsh/AGENTS.md")
            file.parentFile.mkdirs()
            file.writeText("<!-- dsh-app:managed -->\nOld native phone tools\n")
            for (rooted in listOf(false, true)) {
                GuestSetup.writeAgentsMd(root, phoneStorage = true, rootEngine = rooted)
                val text = file.readText()
                assertTrue(text.contains("DeepSeek harness 网页"))
                assertTrue(text.contains("本机文件与命令工具"))
                assertTrue(text.contains("本版没有手机操控"))
                assertFalse(text.contains("mcp__phone__"))
                assertFalse(text.contains("## 可视化回复（dsh-ui）"))
                assertTrue(text.contains("/sdcard/Download/DeepSeek-harness/"))
                assertTrue(text.contains("`/root/workspace`"))
            }
        } finally { root.deleteRecursively() }
    }

    @Test fun liteLeavesUserOwnedInstructionsAndUnrelatedGuestFilesUntouched() {
        val root = kotlin.io.path.createTempDirectory("lite-user").toFile()
        try {
            val file = File(root, "root/.dsh/AGENTS.md")
            file.parentFile.mkdirs()
            val original = "# User-owned instructions\nDo not replace this file.\n".toByteArray()
            file.writeBytes(original)
            GuestSetup.writeAgentsMd(root, phoneStorage = false)
            assertArrayEquals(original, file.readBytes())

            assertArrayEquals(original, file.readBytes())
        } finally { root.deleteRecursively() }
    }
}
