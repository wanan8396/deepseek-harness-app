package app.dsh.rootruntime

import app.dsh.runtime.GuestDependencies
import app.dsh.runtime.SafeMode
import java.io.File
import org.junit.Assert.*
import org.junit.Test

class GuestDependencyLaunchTest {
    private val directory = "/root/.local/share/deepseek-harness/dependencies"
    private val path = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    private fun compose(environment: Map<String, String>) = listOf(
        "libproot.so", "-r", "fixture-root", "-w", "/root", "/usr/bin/env", "-i",
        "HOME=/root", "DSH_HOME=/root/.dsh", "PATH=$path", "TMPDIR=/tmp",
    ) + environment.map { (key, value) -> "$key=$value" } +
        listOf("/bin/sh", "-c", "exec /usr/local/bin/dsh web --no-open")
    private fun plan(environment: Map<String, String>) = RootLaunchPlan.fromProot(
        File("fixture-root"), 10123, 10123, File("fixture-marker"), compose(environment),
    )
    private fun effective(args: List<String>, key: String) = args.last { it.startsWith("$key=") }.substringAfter('=')

    @Test fun managedGuestOverlayKeepsRootAndroidCommandsAndDoesNotIntroduceHostLoaders() {
        val environment = GuestDependencies.environment(mapOf("TZ" to "Asia/Shanghai"), path)
        val composed = compose(environment)
        assertEquals("$directory/tmp", effective(composed, "TMPDIR"))
        val result = plan(environment)
        assertEquals("/usr/bin/env", result.argv.first())
        assertEquals("/root", effective(result.argv, "HOME"))
        assertEquals("/root/.dsh", effective(result.argv, "DSH_HOME"))
        assertEquals("$directory/tmp", effective(result.argv, "TMPDIR"))
        assertEquals("$directory/cache/npm", effective(result.argv, "NPM_CONFIG_CACHE"))
        assertEquals("$directory/cache/pip", effective(result.argv, "PIP_CACHE_DIR"))
        val expected = path + ":$directory/bin:$directory/npm/bin:$directory/python/bin:$directory/cargo/bin:$directory/go/bin" +
            ":/system/bin:/system/xbin:/vendor/bin"
        assertEquals(expected, effective(result.argv, "PATH"))
        assertTrue(result.argv.none { it.startsWith("PROOT_") || it.startsWith("LD_PRELOAD=") || it.startsWith("LD_LIBRARY_PATH=") })
        assertEquals("exec /usr/local/bin/dsh web --no-open", result.argv.last())
    }

    @Test fun normalAndRecoveryProfilesShareToolsWithoutSharingConfigurationHome() {
        val normal = GuestDependencies.environment(emptyMap(), path)
        val recovery = GuestDependencies.environment(SafeMode.GUEST_ENV, path)
        assertEquals(directory, normal["DSH_DEPENDENCY_ROOT"])
        assertEquals(directory, recovery["DSH_DEPENDENCY_ROOT"])
        assertEquals(normal["NPM_CONFIG_PREFIX"], recovery["NPM_CONFIG_PREFIX"])
        assertEquals(normal["TMPDIR"], recovery["TMPDIR"])
        assertEquals(SafeMode.HOME, recovery["DSH_HOME"])
        assertEquals(SafeMode.AGENTS_HOME, recovery["DSH_AGENTS_HOME"])
        assertEquals(SafeMode.HOME, effective(compose(recovery), "DSH_HOME"))
        assertFalse(normal.containsKey("DSH_HOME"))
    }

    @Test fun unmarkedExplicitUserPathContractIsStillUntouched() {
        val result = RootLaunchPlan.fromProot(File("fixture-root"), 10123, 10123, File("fixture-marker"),
            listOf("proot", "/usr/bin/env", "-i", "PATH=/usr/bin:/bin", "PATH=/chosen", "/bin/sh", "-c", "true"))
        assertEquals(listOf("PATH=/usr/bin:/bin", "PATH=/chosen"), result.argv.filter { it.startsWith("PATH=") })
    }
}
