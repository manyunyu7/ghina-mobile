import '../../domain/services/prayer_reminders.dart';
import 'platform_bridge.dart';

/// Android battery-optimisation status + settings shortcut via the Ghina
/// platform bridge (`battery.*` in MainActivity.kt).
class BridgeBatteryOptimization implements BatteryOptimization {
  BridgeBatteryOptimization({PlatformBridge? bridge})
    : _bridge = bridge ?? PlatformBridge();

  final PlatformBridge _bridge;

  @override
  Future<bool?> isIgnoring() => _bridge.isIgnoringBatteryOptimizations();

  @override
  Future<bool> request() => _bridge.openBatteryOptimizationSettings();
}

/// iOS / tests: nothing to exempt.
class NoopBatteryOptimization implements BatteryOptimization {
  const NoopBatteryOptimization();

  @override
  Future<bool?> isIgnoring() async => null;

  @override
  Future<bool> request() async => false;
}
