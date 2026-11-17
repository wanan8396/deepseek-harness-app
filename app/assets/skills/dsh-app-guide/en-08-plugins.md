# Official web plugins

The DeepSeek harness phone shell displays the official webpage; plugins run in the current engine. This uses ordinary official Web plugins, not the old phone-specific native SDK, bridge panels or native plugin market.

## Find plugins

Tap the whale to open the sidebar, then use the webpage's plugin entry. Built-in plugins in official settings differ from dynamic-plugin pages: the former configure bundled components, while the latter provide their own available installation and management actions.

1. Confirm whether the destination is the phone or a computer.
2. Read the plugin's source, version requirements and documentation before using its web install or enable action.
3. Enter plugin settings in its web interface and save if required.
4. Reload or restart only as the webpage requests. Restarting can interrupt work on that engine.

Installing on a computer changes its environment, not the phone. Preserving a profile during an ordinary upgrade does not guarantee compatibility for every third-party plugin.

## A plugin is missing or an action fails

- Check that it is installed on the current engine, enabled and compatible with the version.
- Read the error and restart notice. Retain the failure state rather than assuming another tap succeeded.
- If the official page lacks an entry, do not look for old native SDK buttons, status strips or message-menu placements.
- Install scripts, tools and model calls run on the destination engine. A plugin may access its available files or external services. Use designated fields for service credentials.

## Disable and uninstall

Disabling, uninstalling and deleting plugin data are separate operations. Read the current web confirmation for restart requirements and retained settings or data. Do not apply the old client's uninstall order or undo timing.

This guide does not guarantee that every official listing or third-party plugin suits Android. For startup and compatible upgrades, see [Local runtime](03-engine-hosts.md); for official scheduling, see [Automation tasks](12-automation.md).
