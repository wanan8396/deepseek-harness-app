# Settings and user guide

There are two settings surfaces: the bottom-right control opens the shell's connection settings; the sidebar account menu opens the current engine's official web settings. They do not manage the same data.

## Phone-shell settings

Tap the bottom-right This phone or Connect computer control:

- This phone selects the phone runtime. Install it if required, then wait for startup.
- The permission icon on the phone row opens files, notifications and background permissions. Root is checked automatically on normal local startup; recovery skips the probe and uses PRoot. There is no switch on this page; see [System permissions](04-permissions.md).
- Connect computer provides HTTP/HTTPS address entry, QR scanning and recent-connection selection/removal; see [Web connections](05-web.md).

Selecting phone/computer changes the webpage destination, not the location of existing data. Removing a computer record affects this phone's saved connection, not the computer's records.

## Official web settings

Tap the whale to open the sidebar and use the webpage's account menu or Settings entry. It normally offers General, Models, Account, Built-in plugins and Agent presets; the actual set depends on engine version and plugins.

- Sign-in and model services: [Sign-in and models](02-models.md).
- Plugin management and configuration: [Official web plugins](08-plugins.md).
- Theme, language and web display: [Appearance](09-appearance.md).
- Automation is managed through the webpage's task entry: [Automation tasks](12-automation.md).

Engine or conversation permissions govern official tools' files and commands. Android storage, notifications and Root are separate phone-system permissions.

## Local configuration document

Once the phone runtime is running, opening the configuration file from the official General settings opens the shell's read-only document view. Normal mode reads the current phone profile; recovery mode reads its isolated recovery profile, with the source shown in the view.

The view does not edit, copy or export configuration, and does not return its contents to webpage scripts. Changing connections, stopping the local engine, backgrounding the app or replacing the runtime closes the old view; reopen it from the current phone settings. Computer webpages retain that computer's original handling and do not read phone configuration.

## Check versions and results

The [index](../README.md) identifies the supported version from the bundled runtime's `dshVersion`. Neither an old app-project version field nor another computer's version replaces it. After saving, verify the page's actual read-back. Re-read after disconnection or an unknown result instead of assuming the change took effect.

A compatible ordinary upgrade is not reset and does not retain only the home directory; see [Local runtime](03-engine-hosts.md). This guide does not direct you to old native chat, remote-terminal or phone-autocontrol settings.
