import '../../domain/services/launcher_icon.dart';
import 'platform_bridge.dart';

/// Android: one launcher activity-alias per mascot, switched natively
/// (`LauncherIcon.kt`; `launcherIcon.*` in MainActivity.kt).
class BridgeLauncherIcon implements LauncherIcon {
  BridgeLauncherIcon({PlatformBridge? bridge})
    : _bridge = bridge ?? PlatformBridge();

  final PlatformBridge _bridge;

  @override
  Future<bool> apply(String mascotId) => _bridge.setLauncherIcon(mascotId);
}

/// iOS / tests: the icon stays the tree.
class NoopLauncherIcon implements LauncherIcon {
  const NoopLauncherIcon();

  @override
  Future<bool> apply(String mascotId) async => false;
}
