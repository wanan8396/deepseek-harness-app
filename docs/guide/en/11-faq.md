# Troubleshooting

## The startup animation stays up

Check the destination at the bottom. In phone mode, first installation, engine startup and webpage loading are separate stages. Ordinary waiting uses the looping cover, not percentage progress. Use Retry when an error appears; failures are not solved by endless automatic restarts. If the runtime is missing, install it as prompted rather than clearing data.

In computer mode, check that its service is running and the address/network is reachable. The phone engine's status says nothing about the computer service. Complete a requested PIN or login inside the webpage; see [Web connections](05-web.md).

## A message does not send or a model errors

Check the destination, web connection, login and selected provider/model. A web launch token differs from a model API key. Obtain a fresh login link after expiry; do not send tokens or cookies in chat. Saving settings does not verify service-side access or balance; see [Sign-in and models](02-models.md).

## Background execution stops or a reminder is missing

Check notifications, background operation, battery optimization and vendor auto-start settings on the local permissions page. A confirmed vendor setting means it was checked manually, not that the process will live forever. Reopen after system force-stop; memory and power rules may still end work.

Computer mode does not make computer work local or automatically provide the same local notifications. After returning to the foreground, verify reconnection before checking results.

## The whale or right-hand control is gone

Dismiss the keyboard and close any blocking dialog or overlay. Bottom controls temporarily hide for these layers, but the sidebar itself should not remove the whale. Before web readiness the whale may be inactive. See [Persistent controls](06-navigation.md).

## A three-dot menu is clipped or holding only selects text

Use the three-dot button beside the entry instead of relying on touch-and-hold, and check its target. Small screens, landscape and large system fonts change available space. Scroll the sidebar or close other overlays first. If clipping persists, record orientation, font scaling, menu and reproduction steps.

## The guide and menus differ

First distinguish the shell's connection page from official web settings, then check phone/computer mode and runtime version. Automation uses the current engine's official task page.

## What to include in feedback

Provide the applicable runtime version, Android version, actual Root/PRoot mode or computer-web mode, steps and visible error. Inspect screenshots and text first, removing complete API keys, tokens, cookies, login URLs and personal host addresses. User HOME is not required, and diagnostics or conversation exports are not complete backups.

For upgrades versus reset, see [Local runtime](03-engine-hosts.md); for archive and workspace-deletion effects, see [Conversations](01-chat.md).
