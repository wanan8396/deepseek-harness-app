package app.dsh.launch

import app.dsh.icons.LauncherIcons
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Element
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory

/**
 * The system's launch window never shows an icon other than the chosen 桌面图标: each icon's
 * splash theme names the very icon its launcher entry uses, the blank one none, and the theme
 * chosen for the next launches follows the icon.
 */
class LaunchThemesTest {
    private val main = File("src/main")
    private val ns = "app.dsh"

    private fun xml(file: File): Element = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(file).documentElement

    private fun Element.children(tag: String): List<Element> {
        val nodes = getElementsByTagName(tag)
        return (0 until nodes.length).map { nodes.item(it) as Element }
    }

    private fun styles(): Map<String, Map<String, String>> =
        xml(File(main, "res/values-v31/styles.xml")).children("style").associate { style ->
            style.getAttribute("name") to style.children("item").associate { it.getAttribute("name") to it.textContent.trim() }
        }

    /** Each launcher alias's android:icon, by class name. */
    private fun aliasIcons(): Map<String, String> =
        xml(File(main, "AndroidManifest.xml")).children("activity-alias").associate {
            val name = it.getAttribute("android:name")
            (if (name.startsWith(".")) ns + name else name) to it.getAttribute("android:icon")
        }

    @Test fun eachIconsSplashThemeShowsTheIconItsLauncherEntryShows() {
        val styles = styles()
        val icons = aliasIcons()
        for (alias in LauncherIcons.aliases) {
            val theme = styles[LaunchThemes.forIcon(alias.variant)] ?: error("no theme for ${alias.variant}")
            val entryIcon = icons.getValue(alias.className)
            assertEquals(alias.toString(), entryIcon, theme["android:windowSplashScreenAnimatedIcon"])
            // The same resource the launch screen draws in its first frames.
            assertEquals(alias.toString(), "@mipmap/" + LauncherIcons.mipmapOf(alias.variant), entryIcon)
        }
    }

    /**
     * AOSP (SplashscreenContentDrawer) draws a windowSplashScreenAnimatedIcon 1.2x larger, 192dp
     * instead of the 160dp square the app's first frame takes over from, when the theme's
     * windowSplashScreenIconBackgroundColor is transparent or the splash colour itself.
     */
    @Test fun eachIconsSplashKeepsTheIconInThe160dpSquare() {
        fun colours(dir: String) = xml(File(main, "res/$dir/colors.xml")).children("color")
            .associate { it.getAttribute("name") to it.textContent.trim().uppercase() }
        for ((styleDir, colourDir) in listOf("values-v31" to "values", "values-night-v31" to "values-night")) {
            val colour = colours(colourDir)
            fun resolve(ref: String?) = colour[ref!!.removePrefix("@color/")] ?: error("$colourDir: no colour $ref")
            val launch = xml(File(main, "res/$styleDir/styles.xml")).children("style")
                .single { it.getAttribute("name") == LaunchThemes.BLANK }
                .children("item").associate { it.getAttribute("name") to it.textContent.trim() }
            val ground = resolve(launch["android:windowSplashScreenIconBackgroundColor"])
            val page = resolve(launch["android:windowSplashScreenBackground"])
            assertTrue(styleDir, ground != page)
            assertFalse(styleDir, ground.startsWith("#00"))
        }
        // The icon themes inherit both from LaunchTheme (light or dark) and set only their icon.
        val styles = styles()
        for (variant in LauncherIcons.variants) {
            val theme = styles.getValue(LaunchThemes.forIcon(variant))
            assertEquals(variant, setOf("android:windowSplashScreenAnimatedIcon"), theme.keys)
        }
    }

    @Test fun everyThemeTheSyncCanApplyExists() {
        val styles = styles()
        for (name in LaunchThemes.all) assertTrue(name, name in styles)
    }

    @Test fun theNextLaunchesShowTheChosenIcon() {
        for (variant in LauncherIcons.variants) {
            assertEquals(LaunchThemes.forIcon(variant), LaunchThemes.next(variant))
        }
        assertEquals("LaunchTheme.Night", LaunchThemes.forIcon(LauncherIcons.NIGHT))
    }

    @Test fun onlyTheChosenIconsOwnThemeShowsIt() {
        assertTrue(LaunchThemes.showsIcon("LaunchTheme.Night", LauncherIcons.NIGHT))
        // Another icon's theme (a switch the system didn't take): not this icon.
        assertFalse(LaunchThemes.showsIcon("LaunchTheme.Mist", LauncherIcons.NIGHT))
        assertFalse(LaunchThemes.showsIcon(LaunchThemes.BLANK, LauncherIcons.NIGHT))
        // Nothing applied yet (Android 12, a first launch): blank.
        assertFalse(LaunchThemes.showsIcon(null, LauncherIcons.MIST))
    }

    @Test fun theSystemPageBackgroundTracksDarkMode() {
        assertEquals(LaunchThemes.PAGE_DARK, LaunchThemes.background(dark = true))
        assertEquals(LaunchThemes.PAGE_LIGHT, LaunchThemes.background(dark = false))
    }

    @Test fun pageColoursMatchColorsXml() {
        fun colour(dir: String) = xml(File(main, "res/$dir/colors.xml")).children("color")
            .single { it.getAttribute("name") == "launch_background_top" }.textContent.trim()
        assertEquals("#%08X".format(LaunchThemes.PAGE_LIGHT), colour("values").uppercase())
        assertEquals("#%08X".format(LaunchThemes.PAGE_DARK), colour("values-night").uppercase())
    }
}
