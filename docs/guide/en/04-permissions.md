# System permissions

The DeepSeek harness phone shell uses its permission page for files, notifications and background operation. Normal local-engine starts check Root automatically, with no manual control on this page. Recovery mode skips the Root probe and uses PRoot.

## Open the permission page

Tap the bottom-right This phone/Connect computer control, then the permission icon on the phone row to open local system permissions. First-run setup also shows the system-permissions page. A specific row tap opens Android UI; returning reads detectable state again.

## Files

Storage permission makes the granted phone-file scope available to the local engine, not every app's private data. Consider whether the work needs photos, downloads or documents before granting it. Model tools may modify files within their available access.

Selecting a web attachment differs from exposing phone storage to the engine. To send one file, start with the webpage's attachment action, review the draft, and send it yourself.

## Notifications and background operation

- Allow notifications to see runtime status and the reminders the current product actually supplies. The foreground webpage can still work when system notifications are off.
- Allow background operation, adjust battery optimization if needed, and check the manufacturer's background or auto-start controls.
- Some vendor switches can only be inspected and confirmed by you. A visited or confirmed status is not a system guarantee that the process will stay alive.
- Force-stop, memory pressure and power-saving rules may still end the engine. Reopen the app, inspect the page, and retry if required.

## Automatic Root detection

Each normal local-engine start checks real Android Root once. A verified UID 0 and suitable startup conditions select Root; otherwise the app uses PRoot. Recovery mode skips the Root probe and uses PRoot. The device's Root manager may prompt on the first check. The system-permissions page has no Root grant, disconnect or refresh buttons.

The mode stays fixed while the engine runs. Opening permissions or resuming the app does not trigger another Root probe. The next normal local start checks again. For preserved data, see [Local runtime](03-engine-hosts.md).

## Camera for QR scanning

Computer connection uses camera permission only when you open scanning to read an address QR code. Manual HTTP/HTTPS entry needs no camera. A scan still leads to a preview and confirmation before opening the webpage; see [Web connections](05-web.md).
