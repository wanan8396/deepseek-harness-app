# Appearance and startup

DeepSeek harness retains the official webpage theme and functional layout, adding phone safe areas, a narrow-screen sidebar, keyboard handling and overlay adaptation. It is not a second native chat interface with an independent theme editor.

## Web theme

Use the theme, light/dark or language options offered in the current webpage's account menu or settings. These belong to the current engine or web context; a computer may look different from the phone.

The webpage theme also informs the shell's connection page, permission page and bottom controls so that their light/dark appearance stays coordinated. Before web readiness, the system or last-known theme may appear first and synchronize after loading.

The compact phone settings have no old wallpaper, six-color palette, picture shortcut or custom startup-video editor. Do not look for them using older screenshots.

## Startup animation

Cold start, connection recovery, local-engine waiting and initial webpage loading use the bundled whale cover: the original 40-frame looping GIF, not a still screenshot.

- The animation means waiting, not percentage progress.
- It leaves when the page is ready, without enforcing a full loop.
- For engine or webpage errors, use the error page's Retry action. Repeatedly tapping the cover does not repair startup.
- It scales to the screen's available space and orientation; it should not remain over a ready webpage indefinitely.

## Layout and readability

The bottom controls hide with the keyboard and return after it closes. The sidebar scrolls, and menus and dialogs should stay within usable screen space. Theme changes do not change the meaning of delete, send or permission actions.

For clipped menus, compressed text or mismatched light/dark colors, record orientation, font scaling, webpage version and the exact entry; see [Troubleshooting](11-faq.md). For the whale's function, see [Persistent controls](06-navigation.md).
