/// Compile-time edition switch. The full upstream build stays available for
/// comparison; build-local-web-apk.sh selects the phone-local, web-only edition.
const localWebLite = bool.fromEnvironment('DSH_LOCAL_WEB_LITE', defaultValue: false);

/// Edition capabilities also gate state restoration and side effects, not just UI.
const phoneControlCapability = !localWebLite;
const companionCapability = !localWebLite;
