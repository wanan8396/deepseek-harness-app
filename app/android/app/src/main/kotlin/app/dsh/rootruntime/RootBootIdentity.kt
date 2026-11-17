package app.dsh.rootruntime

import java.math.BigDecimal
import java.math.RoundingMode

/** PID/starttime and mount namespace inode numbers are unique only within one boot. */
internal object RootBootIdentity {
    private val uuid = Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")

    fun valid(value: String): String = value.trim().also { require(uuid.matches(it)) { "root_cleanup_boot" } }

    fun previousBoot(recordedBoot: String?, currentBoot: String, started: String,
        uptimeSeconds: String, ticksPerSecond: Long): Boolean {
        val current = valid(currentBoot)
        if (recordedBoot != null) return valid(recordedBoot).lowercase() != current.lowercase()
        // Pre-bootId records have one strict proof: their starttime is beyond this
        // boot's entire lifetime. Missing/reused PIDs or namespace names alone prove nothing.
        require(started.toLongOrNull()?.let { it > 0 } == true && started.all { it in '0'..'9' } &&
            ticksPerSecond in 1..1_000_000) { "root_cleanup_boot" }
        require(uptimeSeconds.matches(Regex("[0-9]+(?:\\.[0-9]+)?"))) { "root_cleanup_boot" }
        val lifetime = BigDecimal(uptimeSeconds).multiply(BigDecimal.valueOf(ticksPerSecond))
            .setScale(0, RoundingMode.CEILING).add(BigDecimal.valueOf(ticksPerSecond))
        return BigDecimal(started) > lifetime
    }
}
