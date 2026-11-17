package app.dsh.wire

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import org.junit.Assert.*
import org.junit.Test

/** Known wire bytes are independent of either the old or the new encoder. */
class FramesCompatibilityTest {
    @Test fun preservesTheOriginalMagicAndBigEndianFraming() {
        val encoded = ByteArrayOutputStream().apply {
            write(Frames.MAGIC)
            Frames.write(this, byteArrayOf(0x10, 0x20, 0x7f))
            Frames.write(this, byteArrayOf())
        }.toByteArray()
        val legacyFixture = byteArrayOf(0x44, 0x53, 0x48, 0x56, 0, 0, 0, 3, 0x10, 0x20, 0x7f, 0, 0, 0, 0)
        assertArrayEquals(legacyFixture, encoded)
        val stream = ByteArrayInputStream(legacyFixture)
        assertTrue(Frames.syncToMagic(stream))
        assertArrayEquals(byteArrayOf(0x10, 0x20, 0x7f), Frames.read(stream))
        assertArrayEquals(byteArrayOf(), Frames.read(stream))
        assertNull(Frames.read(stream))
    }

    @Test fun toleratesLeadingNoiseAndRejectsTruncatedOrOversizedFrames() {
        assertTrue(Frames.syncToMagic(ByteArrayInputStream(byteArrayOf(0, 0x44, 0x53, 0x48, 0x56))))
        assertFalse(Frames.syncToMagic(ByteArrayInputStream(byteArrayOf(0x44, 0x53))))
        assertThrows(IOException::class.java) { Frames.read(ByteArrayInputStream(byteArrayOf(0, 0, 0))) }
        assertThrows(IOException::class.java) { Frames.read(ByteArrayInputStream(byteArrayOf(0, 0, 0, 2, 1))) }
        assertThrows(IOException::class.java) { Frames.read(ByteArrayInputStream(byteArrayOf(0, 0x80.toByte(), 0, 1))) }
    }
}
