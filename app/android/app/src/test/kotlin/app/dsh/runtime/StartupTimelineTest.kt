package app.dsh.runtime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class StartupTimelineTest {
    @Test fun launchStartIncludesTheAppPart() {
        val t = StartupTimeline(processStart = 1_000)
        t.requested(now = 1_640)
        t.launcherEntered(now = 1_760)
        assertEquals("[dsh-app] startup: app 640 ms, prepare 120 ms, launcher-to-listening 2300 ms", t.ready(now = 4_060))
    }

    @Test fun laterStartsLeaveTheAppPartOut() {
        assertEquals(
            "[dsh-app] startup: prepare 80 ms, launcher-to-listening 1900 ms",
            StartupTimeline.line(processStart = 1_000, requested = 600_000, spawned = 600_080, ready = 601_980),
        )
        assertEquals(
            "[dsh-app] startup: prepare 80 ms, launcher-to-listening 1900 ms",
            StartupTimeline.line(processStart = null, requested = 5_000, spawned = 5_080, ready = 6_980),
        )
    }

    @Test fun separatesLauncherFromGuestAndResetsOnRestart() {
        val t = StartupTimeline(processStart = null)
        t.requested(now = 1_000)
        t.launcherEntered(now = 1_100)
        t.guestReleased(now = 1_700)
        assertEquals("[dsh-app] startup: prepare 100 ms, launcher 600 ms, guest-to-listening 1300 ms", t.ready(now = 3_000))
        t.requested(now = 4_000)
        t.launcherEntered(now = 4_200)
        assertEquals("[dsh-app] startup: prepare 200 ms, launcher-to-listening 800 ms", t.ready(now = 5_000))
    }

    @Test fun ignoresGuestMarksOutsideTheLaunchWindow() {
        val t = StartupTimeline(processStart = null)
        t.requested(now = 1_000)
        t.launcherEntered(now = 1_200)
        t.guestReleased(now = 1_199)
        assertEquals("[dsh-app] startup: prepare 200 ms, launcher-to-listening 800 ms", t.ready(now = 2_000))
        t.guestReleased(now = 2_001)
        assertEquals("[dsh-app] startup: prepare 200 ms, launcher-to-listening 800 ms", t.ready(now = 2_000))
    }

    @Test fun nothingWithoutTheEarlierMarks() {
        val t = StartupTimeline(processStart = 1_000)
        assertNull(t.ready(now = 2_000))
        t.requested(now = 1_500)
        assertNull("not spawned yet", t.ready(now = 2_000))
        t.launcherEntered(now = 1_600)
        t.requested(now = 3_000)
        assertNull("a new start clears the old spawn", t.ready(now = 3_500))
    }
}
