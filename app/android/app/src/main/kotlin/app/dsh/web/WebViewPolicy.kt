package app.dsh.web

/** WebView bridge values validated independently of the Flutter platform-view lookup. */
object WebViewPolicy {
    fun textZoom(percent: Int): Int = percent.coerceIn(50, 300)
    fun webViewId(raw: Any?): Long? = when (raw) {
        is Int -> raw.toLong()
        is Long -> raw
        else -> null
    }
}
