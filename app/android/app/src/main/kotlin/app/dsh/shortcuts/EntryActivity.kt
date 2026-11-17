package app.dsh.shortcuts

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Bundle
import app.dsh.MainActivity

/**
 * Where the launcher shortcuts (res/xml/shortcuts.xml and the recent conversations) and the
 * Quick Settings tile point: hands the entry to the app's own task as
 * [ShortcutsPlugin.ACTION_ENTRY], stamped with [ShortcutsPlugin.token].
 *
 * Not exported. Launchers start shortcuts as the publishing app and the tile's PendingIntent is
 * ours, so only those reach it; MainActivity is exported, so the token proves an entry came through
 * this process.
 */
class EntryActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val kind = kindOf(intent.action)
        if (kind != null || intent.action == ACTION_OPEN_APP) {
            val forward = Intent(this, MainActivity::class.java).apply {
                if (kind != null) {
                    action = ShortcutsPlugin.ACTION_ENTRY
                    putExtra(ShortcutsPlugin.EXTRA_KIND, kind)
                    intent.getStringExtra(EXTRA_SESSION)?.let { putExtra(ShortcutsPlugin.EXTRA_SESSION, it) }
                    intent.getStringExtra(EXTRA_HOST)?.let { putExtra(ShortcutsPlugin.EXTRA_HOST, it) }
                    putExtra(ShortcutsPlugin.EXTRA_TOKEN, ShortcutsPlugin.token)
                }
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            try {
                startActivity(forward)
            } catch (_: Exception) {
            }
        }
        finish()
        @Suppress("DEPRECATION")
        overridePendingTransition(0, 0)
    }

    companion object {
        const val ACTION_NEW_CHAT = "app.dsh.action.NEW_CHAT"
        const val ACTION_OPEN_CHAT = "app.dsh.action.OPEN_CHAT"
        private const val ACTION_OPEN_APP = "app.dsh.action.OPEN_APP"
        const val EXTRA_SESSION = "session_id"
        const val EXTRA_HOST = "host"

        fun kindOf(action: String?): String? = when (action) {
            ACTION_NEW_CHAT -> ShortcutsPlugin.KIND_NEW
            ACTION_OPEN_CHAT -> ShortcutsPlugin.KIND_CHAT
            else -> null
        }

        fun newChat(context: Context): Intent = Intent(context, EntryActivity::class.java).setAction(ACTION_NEW_CHAT)

        fun openApp(context: Context): Intent = Intent(context, EntryActivity::class.java).setAction(ACTION_OPEN_APP)

        fun openChat(context: Context, sessionId: String, host: String?): Intent =
            Intent(context, EntryActivity::class.java).setAction(ACTION_OPEN_CHAT).apply {
                putExtra(EXTRA_SESSION, sessionId)
                if (host != null) putExtra(EXTRA_HOST, host)
            }
    }
}
