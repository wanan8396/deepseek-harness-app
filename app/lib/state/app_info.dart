/// Metadata shown by the current Android phone shell.
abstract final class AppInfo {
  static const version = String.fromEnvironment('DSH_APP_VERSION', defaultValue: '1.0.15+1');
  static String get displayVersion => version.split('+').first;
  static const name = 'DeepSeek harness';
}
