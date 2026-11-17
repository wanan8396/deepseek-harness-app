package app.dsh.rootruntime

import org.junit.Assert.*
import org.junit.Test

class RootBootIdentityTest {
    private val current = "11111111-2222-4333-8444-555555555555"
    private val former = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"

    @Test fun differentBootRetiresOldIdentityEvenWhenPidAndNamespaceNumbersAreReused() {
        assertTrue(RootBootIdentity.previousBoot(former, current, "48296240", "1067.86", 100))
        assertTrue(RootBootIdentity.previousBoot(former, current, "100", "99999999.00", 100))
    }

    @Test fun sameBootNeverUsesLegacyTimeFallbackOrCaseDifferences() {
        assertFalse(RootBootIdentity.previousBoot(current, current, "48296240", "1067.86", 100))
        assertFalse(RootBootIdentity.previousBoot(former.uppercase(), former, "48296240", "1067.86", 100))
    }

    @Test fun capturedPreBootIdRecordIsProvenOlderThanTheEntireCurrentBoot() {
        assertTrue(RootBootIdentity.previousBoot(null, current, "48296240", "1067.86", 100))
        assertFalse(RootBootIdentity.previousBoot(null, current, "13758", "1067.86", 100))
    }

    @Test fun timestampBoundaryIncludesAConservativeOneSecondMargin() {
        assertFalse(RootBootIdentity.previousBoot(null, current, "1000", "10.00", 100))
        assertFalse(RootBootIdentity.previousBoot(null, current, "1100", "10.00", 100))
        assertTrue(RootBootIdentity.previousBoot(null, current, "1101", "10.00", 100))
        assertFalse(RootBootIdentity.previousBoot(null, current, "1101", "10.001", 100))
        assertTrue(RootBootIdentity.previousBoot(null, current, "1102", "10.001", 100))
    }

    @Test fun malformedPresentBootIdNeverFallsBackToLegacyProof() {
        for (bad in listOf("", "not-a-uuid", "null", current + " suffix")) {
            invalid { RootBootIdentity.previousBoot(bad, current, "48296240", "10.00", 100) }
            invalid { RootBootIdentity.previousBoot(null, bad, "48296240", "10.00", 100) }
        }
    }

    @Test fun missingOrInvalidClockEvidenceCannotRetireAnUnknownNamespace() {
        for (started in listOf("", "-1", "0", "+10", "1.0", "9223372036854775808")) {
            invalid { RootBootIdentity.previousBoot(null, current, started, "10.00", 100) }
        }
        for (uptime in listOf("", "-1", "NaN", "Infinity", "1e3", "10.00 ignored")) {
            invalid { RootBootIdentity.previousBoot(null, current, "48296240", uptime, 100) }
        }
        for (rate in listOf(-1L, 0L, 1_000_001L)) {
            invalid { RootBootIdentity.previousBoot(null, current, "48296240", "10.00", rate) }
        }
    }

    private fun invalid(action: () -> Unit) {
        try { action(); fail("Incomplete boot evidence must remain blocked") }
        catch (_: IllegalArgumentException) { }
    }
}
