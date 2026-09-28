import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Build-time fallback (`--dart-define=APP_VERSION=…`), used when the platform
/// can't be asked (tests, desktop without the plugin).
const _fallbackVersion = String.fromEnvironment('APP_VERSION');

/// The installed app's version name (e.g. `1.0.8`) from the platform
/// (`package_info_plus`, i.e. pubspec `version:` of the running build).
Future<String> readAppVersion() async {
  try {
    final info = await PackageInfo.fromPlatform();
    if (info.version.isNotEmpty) return info.version;
  } catch (e) {
    debugPrint('package_info failed: $e');
  }
  return _fallbackVersion;
}
