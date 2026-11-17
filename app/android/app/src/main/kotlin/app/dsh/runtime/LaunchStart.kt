package app.dsh.runtime

import android.content.Context
import android.os.Handler
import android.os.Looper
import org.json.JSONObject

/**
 * 「打开 App 时自动启动」 as soon as the activity is created. The app root (RootGate,
 * app/lib/ui/shell/root_gate.dart) asks for the same start once Flutter is up, settings and the
 * runtime status have loaded and the first frame is out: about half a second later on an
 * emulator, more on a phone. Starting here boots DSH alongside Flutter; RootGate's own start()
 * then finds the engine starting and changes nothing.
 */
object LaunchStart {
    /** Flutter's shared_preferences store and its keys (app/lib/state/settings_state.dart). */
    private const val FLUTTER_PREFS = "FlutterSharedPreferences"
    private const val K_PHONE_STORAGE = "flutter.phone_storage"
    private const val K_WEB_CONNECTION = "flutter.web_connection.v1"

    private var liteGeneration = 0L
    @Volatile internal var liteAppOpen = false
        private set
    private var litePending: Pair<RuntimeController, RuntimeController.EventSink>? = null

    /**
     * This process's own start of the engine: true once it asked for one, false when the rule said
     * no (or it failed); null before it has decided. The launch screen reads it
     * (launch/LaunchScreen.kt): a start under way is a cold start, worth covering.
     */
    @Volatile var decided: Boolean? = null
        private set

    /** Each real activity entry follows the current local/computer connection. */
    fun onActivityCreate(context: Context, live: () -> Boolean = { true }) {
        startLiteWhenReady(context.applicationContext, live)
    }

    internal fun isComputerConnection(raw: String?): Boolean =
        raw != null && runCatching { JSONObject(raw).optString("mode") == "computer" }.getOrDefault(false)

    internal fun shouldAllowLocalRuntime(appOpen: Boolean, computer: Boolean): Boolean =
        appOpen && !computer

    internal fun localRuntimeAllowed(context: Context): Boolean {
        val computer = isComputerConnection(context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            .getString(K_WEB_CONNECTION, null))
        return shouldAllowLocalRuntime(liteAppOpen, computer)
    }

    internal fun shouldStartLite(computer: Boolean, phase: String?): Boolean =
        !computer && phase in setOf(RuntimeController.Phase.INSTALLED.wire, RuntimeController.Phase.ERROR.wire)

    internal fun shouldStopOnDestroy(finishing: Boolean, changingConfigurations: Boolean): Boolean =
        finishing && !changingConfigurations

    /** Main-thread cancellation also invalidates an already posted activity-start callback. */
    internal fun cancelLiteStart() {
        liteAppOpen = false
        liteGeneration++
        clearLitePending()
        decided = false
    }

    private fun clearLitePending() {
        litePending?.let { (controller, sink) -> controller.removeSink(sink) }
        litePending = null
    }

    private fun startLiteWhenReady(app: Context, live: () -> Boolean) {
        cancelLiteStart()
        liteAppOpen = true
        val generation = liteGeneration
        decided = null
        Handler(Looper.getMainLooper()).post {
            if (generation != liteGeneration || !live()) return@post
            val prefs = app.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            fun computer() = isComputerConnection(prefs.getString(K_WEB_CONNECTION, null))
            if (computer()) { decided = false; return@post }
            val controller = RuntimeController.get(app)
            fun attempt() {
                if (generation != liteGeneration) return
                if (!live() || computer()) { clearLitePending(); decided = false; return }
                val phase = controller.phase.wire
                // Reopening while the previous process stops, or finishing first install, is not a missed start.
                if (phase in setOf("notInstalled", "installing", "stopping")) return
                clearLitePending()
                if (!shouldStartLite(false, phase)) { decided = phase in setOf("starting", "running"); return }
                decided = runCatching {
                    controller.start(phoneStorage = prefs.getBoolean(K_PHONE_STORAGE, false))
                }.isSuccess
            }
            val sink = RuntimeController.EventSink { event -> if (event["type"] == "status") attempt() }
            litePending = controller to sink
            controller.addSink(sink)
            attempt()
        }
    }

}
