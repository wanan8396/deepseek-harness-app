package app.dsh.wire

import java.io.InputStream
import java.io.OutputStream

/**
 * Length-prefixed frames for the app's private Root-runtime transport.
 * Uses only java.io so the same framing is covered by JVM tests.
 */
object Frames {
    const val MAX = 8 * 1024 * 1024

    /** Written once before the first frame so the reader can skip leading shell/stderr noise. */
    val MAGIC = byteArrayOf('D'.code.toByte(), 'S'.code.toByte(), 'H'.code.toByte(), 'V'.code.toByte())

    /** Reads and discards input until [MAGIC] is matched; false at end of stream. */
    fun syncToMagic(input: InputStream): Boolean {
        var matched = 0
        while (matched < MAGIC.size) {
            val b = input.read()
            if (b < 0) return false
            matched = if (b.toByte() == MAGIC[matched]) matched + 1
            else if (b.toByte() == MAGIC[0]) 1 else 0
        }
        return true
    }

    fun write(out: OutputStream, payload: ByteArray) {
        require(payload.size <= MAX) { "frame too large" }
        val n = payload.size
        out.write(byteArrayOf((n ushr 24).toByte(), (n ushr 16).toByte(), (n ushr 8).toByte(), n.toByte()))
        out.write(payload)
        out.flush()
    }

    /** Blocks for a full frame; null at clean end of stream. */
    fun read(input: InputStream): ByteArray? {
        val header = readFully(input, 4) ?: return null
        val n = ((header[0].toInt() and 0xff) shl 24) or ((header[1].toInt() and 0xff) shl 16) or
            ((header[2].toInt() and 0xff) shl 8) or (header[3].toInt() and 0xff)
        if (n < 0 || n > MAX) throw java.io.IOException("bad frame length $n")
        return readFully(input, n) ?: throw java.io.IOException("truncated frame")
    }

    private fun readFully(input: InputStream, n: Int): ByteArray? {
        val buf = ByteArray(n)
        var off = 0
        while (off < n) {
            val r = input.read(buf, off, n - off)
            if (r < 0) return if (off == 0) null else throw java.io.IOException("truncated")
            off += r
        }
        return buf
    }
}
