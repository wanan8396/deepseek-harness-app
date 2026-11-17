package app.dsh.web

import org.junit.Assert.*
import org.junit.Test

class WebViewPolicyTest {
    @Test fun onlyFlutterIntegerIdentifiersReachTheViewLookup() {
        assertEquals(7L, WebViewPolicy.webViewId(7))
        assertEquals(7L, WebViewPolicy.webViewId(7L))
        assertNull(WebViewPolicy.webViewId("7"))
        assertNull(WebViewPolicy.webViewId(7.0))
        assertNull(WebViewPolicy.webViewId(null))
    }

    @Test fun zoomIsBoundedWithoutChangingTheCurrentThemeRules() {
        assertEquals(50, WebViewPolicy.textZoom(0))
        assertEquals(100, WebViewPolicy.textZoom(100))
        assertEquals(300, WebViewPolicy.textZoom(1000))
    }
}
