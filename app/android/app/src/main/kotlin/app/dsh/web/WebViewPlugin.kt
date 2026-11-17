package app.dsh.web

import android.app.ActivityManager
import android.content.Context
import android.os.Debug
import android.os.Handler
import android.os.Looper
import android.webkit.WebView
import androidx.webkit.WebViewCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.webviewflutter.WebViewFlutterAndroidExternalApi

/** Current shell WebView integration; the existing channel name remains wire-compatible. */
class WebViewPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var binding: FlutterPlugin.FlutterPluginBinding? = null
    private var methods: MethodChannel? = null
    private val main = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        this.binding = binding
        methods = MethodChannel(binding.binaryMessenger, "dsh/islands").also { it.setMethodCallHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods?.setMethodCallHandler(null)
        methods = null
        this.binding = null
    }

    private fun webView(call: MethodCall): Pair<Long, WebView>? {
        val id = WebViewPolicy.webViewId(call.argument<Any>("id")) ?: return null
        val binding = binding ?: return null
        val view = runCatching { WebViewFlutterAndroidExternalApi.getWebView(binding, id) }.getOrNull() ?: return null
        return id to view
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "device" -> result.success(device())
            "appPss" -> result.success(Debug.getPss().toInt())
            "attach" -> {
                val (id, view) = webView(call) ?: return result.success(false)
                ShellWebViews.setDark(view, call.argument<Boolean>("dark") == true)
                call.argument<Int>("textZoom")?.let { ShellWebViews.setTextZoom(view, it) }
                ShellWebViews.guard(view) { crashed ->
                    main.post { methods?.invokeMethod("rendererGone", mapOf("id" to id, "crashed" to crashed)) }
                }
                result.success(true)
            }
            "setDark" -> {
                webView(call)?.let { (_, view) -> ShellWebViews.setDark(view, call.argument<Boolean>("dark") == true) }
                result.success(null)
            }
            "setTextZoom" -> {
                val zoom = call.argument<Int>("zoom")
                webView(call)?.let { (_, view) -> if (zoom != null) ShellWebViews.setTextZoom(view, zoom) }
                result.success(null)
            }
            "destroy" -> {
                webView(call)?.let { (_, view) -> runCatching { ShellWebViews.destroy(view) } }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun device(): Map<String, Any?> {
        val ctx = binding?.applicationContext ?: return emptyMap()
        val am = ctx.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val info = ActivityManager.MemoryInfo().also { am.getMemoryInfo(it) }
        val provider = runCatching { WebViewCompat.getCurrentWebViewPackage(ctx) }.getOrNull()
        return mapOf(
            "totalMem" to info.totalMem, "availMem" to info.availMem, "lowRam" to am.isLowRamDevice,
            "webView" to provider?.let { "${it.packageName} ${it.versionName}" },
        )
    }
}
