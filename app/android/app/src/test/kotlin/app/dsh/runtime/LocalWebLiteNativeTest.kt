package app.dsh.runtime

import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.*
import org.junit.Test
import org.w3c.dom.Element

/** Source/manifest contracts; the merged APK and actual launch still require the build check. */
class LocalWebLiteNativeTest {
    private val source = File("src/main/kotlin/app/dsh")
    private val android = "http://schemas.android.com/apk/res/android"
    private fun manifest(): Element = DocumentBuilderFactory.newInstance().apply { isNamespaceAware = true }
        .newDocumentBuilder().parse(File("src/main/AndroidManifest.xml")).documentElement
    private fun Element.elements(tag: String): List<Element> = getElementsByTagName(tag).let { nodes ->
        (0 until nodes.length).map { nodes.item(it) as Element }
    }
    private fun Element.name(): String = getAttributeNS(android, "name")

    @Test fun retiredNativeSourcesAndReflectiveEntryPointsAreActuallyAbsent() {
        assertFalse(File("src/full").exists())
        for (name in listOf("phone", "pet", "companion", "voice", "media", "islands", "nativefiles", "nativemedia", "usage")) {
            assertFalse(name, File(source, name).exists())
        }
        for (name in listOf("FullPlugins.kt", "runtime/PhoneHooks.kt", "runtime/GuestPhoneOverlay.kt",
            "runtime/PhoneSkillWrite.kt", "runtime/PhoneSkillInstaller.kt", "runtime/PhoneSkillBundleReader.kt",
            "runtime/PhoneSkillBundleInstaller.kt", "runtime/GuestSkillRoute.kt", "runtime/GuestSkillDescriptors.kt",
            "runtime/GuestSkillBounds.kt", "runtime/GuestScreen.kt", "runtime/GuestJson.kt",
            "runtime/DirectLaunch.kt", "runtime/LegacyRuntimePaths.kt", "runtime/RetiredPhoneConfig.kt",
            "runtime/LastKnownGood.kt", "diagnostics/SystemImePrompt.kt", "diagnostics/SystemImeLogcat.kt",
            "diagnostics/SystemImeEvidence.kt", "notify/NotifyFeatures.kt", "launch/LaunchClipPlugin.kt",
            "files/SelectedFilesPlugin.kt", "files/SelectedFileBudget.kt")) {
            assertFalse(name, File(source, name).exists())
        }
        val forbidden = Regex("""import app\.dsh\.(phone|pet|companion|voice|media|islands|nativefiles|nativemedia|usage)\b|FullPlugins|PhoneHooks|GuestPhoneOverlay|LegacyRuntimePaths|RetiredPhoneConfig|LaunchClipPlugin|dsh/launch_clip|SelectedFilesPlugin|SelectedFileBudget|dsh/native-files""")
        for (file in source.walkTopDown().filter { it.extension == "kt" }) {
            assertFalse(file.path, forbidden.containsMatchIn(file.readText()))
        }
    }

    @Test fun mainManifestHasNoOldComponentsOrPrivilegesToMask() {
        val main = manifest()
        val names = listOf("activity", "service", "provider", "receiver").flatMap { main.elements(it) }.map { it.name() }
        assertFalse(names.any { it.contains(".phone.") || it.contains(".pet.") || it.contains(".companion.") || it.contains("shizuku") })
        assertTrue(names.contains(".runtime.DshService"))
        assertTrue(names.contains(".notify.NotifyActionReceiver"))
        assertTrue(names.contains("androidx.core.content.FileProvider"))
        val permissions = main.elements("uses-permission").map { it.name() }.toSet()
        for (name in listOf("android.permission.RECEIVE_BOOT_COMPLETED", "android.permission.WRITE_SECURE_SETTINGS",
            "com.android.alarm.permission.SET_ALARM", "moe.shizuku.manager.permission.API_V23",
            "android.permission.SYSTEM_ALERT_WINDOW", "android.permission.RECORD_AUDIO",
            "android.permission.REQUEST_INSTALL_PACKAGES")) assertFalse(name, name in permissions)
        assertTrue(permissions.containsAll(setOf("android.permission.INTERNET", "android.permission.ACCESS_NETWORK_STATE",
            "android.permission.WAKE_LOCK", "android.permission.FOREGROUND_SERVICE", "android.permission.POST_NOTIFICATIONS",
            "android.permission.MANAGE_EXTERNAL_STORAGE", "android.permission.CAMERA")))
        assertFalse(File("src/localWebLite/AndroidManifest.xml").exists())
    }

    @Test fun gradleHasNoCompileTimeProductSwitchOrFullSourceFlavor() {
        val gradle = File("build.gradle.kts").readText()
        for (name in listOf("src/full", "androidComponents", "shizuku", "libadb", "conscrypt", "bouncycastle", "text-recognition-chinese")) {
            assertFalse(name, gradle.contains(name))
        }
        assertFalse("compile-time product switch", gradle.contains("LOCAL_WEB_LITE"))
        assertTrue(gradle.contains("applicationId = \"app.dsh\""))
        // Keep the current Lite visual resources byte-for-byte, independently of any Dart define.
        assertEquals(2, Regex("""res.srcDir\("src/localWebLite/res"\)""").findAll(gradle).count())
        assertTrue(gradle.contains("arm64-v8a/assets"))
        assertTrue(gradle.contains("x86_64/assets"))
        val rules = File("proguard-rules.pro").readText()
        assertTrue(rules.contains("app.dsh.rootruntime.RootLaunchMain"))
        assertTrue(rules.contains("app.dsh.rootruntime.RootNamespaceMain"))
        assertFalse(rules.contains("app.dsh.phone"))
    }

    @Test fun activityKeepsCurrentShellChannelsAndWebViewSupport() {
        val activity = File(source, "MainActivity.kt").readText()
        for (registration in listOf("RuntimePlugin()", "NotifyPlugin()", "FilesPlugin()",
            "LinksPlugin()", "SharePlugin()", "ShortcutsPlugin()", "DiagnosticsPlugin()", "WebFilesPlugin()", "WebViewPlugin()")) {
            assertTrue(registration, activity.contains(registration))
        }
        assertTrue(activity.contains("MlKitRuntime.initialize(applicationContext)"))
        assertTrue(activity.contains("LaunchThemeSync.sync(this)"))
        assertFalse(activity.contains("LaunchClipPlugin"))
        val launch = File(source, "launch/LaunchScreen.kt").readText()
        for (method in listOf("begin", "syncTheme", "reveal", "mark", "done")) {
            assertTrue(method, launch.contains("\"$method\""))
        }
        assertFalse(launch.contains("\"snapshot\""))
        val web = File(source, "web/WebViewPlugin.kt").readText()
        assertTrue(web.contains("\"dsh/islands\""))
        for (method in listOf("attach", "setDark", "setTextZoom", "destroy", "device", "appPss", "rendererGone")) {
            assertTrue(method, web.contains("\"$method\""))
        }
    }

    @Test fun runtimeRequiresOfficialDistributionAndHasNoExecutableLegacyAdapters() {
        val controller = File(source, "runtime/RuntimeController.kt").readText()
        val process = File(source, "runtime/DshProcess.kt").readText()
        assertTrue(controller.contains("check(officialLocalWeb)"))
        assertTrue(process.contains("check(OfficialRuntime.isUnmodified("))
        assertTrue(controller.contains("OfficialPhoneSkills.sync(installer.rootfs"))
        for (text in listOf(controller, process)) {
            for (name in listOf("PhoneSkillOrigin", "savePhoneSkill", "readPhoneSkillBundle", "checkPhoneSkillSave",
                "DSH_GO_RUNTIME_ROOT", "prootNodeOptions", "GuestPhoneOverlay", "PhoneHooks", "--patch")) assertFalse(name, text.contains(name))
        }
        val diagnostics = File(source, "diagnostics/DiagnosticsPlugin.kt").readText()
        assertFalse(diagnostics.contains("collectSystemIme"))
        assertFalse(diagnostics.contains("VoiceDiagnostics"))
        assertFalse(diagnostics.contains("backgroundInputProbe"))
    }
}
