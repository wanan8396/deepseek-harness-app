package app.dsh.launch

import android.app.Activity
import android.content.Context
import android.content.res.Configuration
import android.content.res.Resources
import android.os.Build
import android.util.Log
import app.dsh.R
import app.dsh.icons.LauncherIconPlugin
import app.dsh.icons.LauncherIcons

/**
 * Which theme the system's launch window is drawn from, so that it never shows an icon other than
 * the one the person chose (桌面图标) or the page colour.
 * Pure, unit-tested on the JVM; [LaunchThemeSync] applies it.
 *
 * A theme is fixed per activity, and an activity-alias can't have its own, so the manifest's
 * LaunchTheme can't know which icon is on the launcher. It shows none: the page colour alone
 * (12+: a transparent splash icon; 8–11: a window background without the icon). Android 13
 * lets an app choose the splash theme of its next launches (SplashScreen.setSplashScreenTheme):
 * there the chosen icon's own theme (LaunchTheme.Night …) is kept in place, so from then on the
 * splash shows that icon. A system that ignores the choice falls back to the blank theme, never
 * to another icon.
 */
internal object LaunchThemes {
    /** The manifest's LaunchTheme: the page colour, no icon. */
    const val BLANK = "LaunchTheme"

    /** The splash with [variant]'s icon (LauncherIcons.variants). */
    fun forIcon(variant: String): String = "LaunchTheme." + variant.replaceFirstChar { it.uppercaseChar() }

    /** Themes selectable for current launches, in R.style order of [LaunchThemeSync]. */
    val all: List<String> get() = listOf(BLANK) + LauncherIcons.variants.map(::forIcon)

    /** The next system splash always follows the selected launcher icon. */
    fun next(icon: String): String = forIcon(icon)

    /** Whether a launch drawn from [applied] shows [icon] in the splash. */
    fun showsIcon(applied: String?, icon: String): Boolean = applied != null && applied == forIcon(icon)

    /** The background the splash of [applied] lays (ARGB), [dark] for the page colour. */
    fun background(dark: Boolean): Int = if (dark) PAGE_DARK else PAGE_LIGHT

    /** res/values{,-night}/colors.xml launch_background_top (LaunchGeometryTest keeps them equal). */
    const val PAGE_LIGHT = 0xFFEBF1FE.toInt()
    const val PAGE_DARK = 0xFF1D222C.toInt()
}

/**
 * Keeps Android 13+'s splash theme on [LaunchThemes.next] (applied for the next launches), and
 * remembers what was applied: a launch reads it to know what its own splash showed.
 */
internal object LaunchThemeSync {
    private const val TAG = "DshLaunch"
    private const val PREFS = "launch_theme"
    private const val KEY_APPLIED = "applied"

    /** The splash theme this launch was drawn from (null: the manifest's, blank). */
    fun applied(context: Context): String? = if (Build.VERSION.SDK_INT >= 33) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_APPLIED, null)
    } else {
        null
    }

    fun dark(context: Context) =
        (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES

    /** Brings the next launches' splash theme in line with the launcher icon. Main thread. */
    fun sync(activity: Activity) {
        if (Build.VERSION.SDK_INT < 33) return
        try {
            val want = LaunchThemes.next(LauncherIconPlugin.current(activity))
            val prefs = activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            if (prefs.getString(KEY_APPLIED, null) == want) return
            activity.splashScreen.setSplashScreenTheme(styleOf(want))
            prefs.edit().putString(KEY_APPLIED, want).commit()
        } catch (e: Exception) {
            // Not applied: the next launch is taken to be blank (it never assumes an icon).
            Log.w(TAG, "splash theme: ${e.javaClass.simpleName}")
            activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(KEY_APPLIED).commit()
        }
    }

    private fun styleOf(name: String): Int = when (name) {
        LaunchThemes.forIcon(LauncherIcons.MIST) -> R.style.LaunchTheme_Mist
        LaunchThemes.forIcon(LauncherIcons.NIGHT) -> R.style.LaunchTheme_Night
        LaunchThemes.forIcon(LauncherIcons.FROST) -> R.style.LaunchTheme_Frost
        LaunchThemes.forIcon(LauncherIcons.INK) -> R.style.LaunchTheme_Ink
        else -> Resources.ID_NULL
    }
}
