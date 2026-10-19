import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/data/notifications/flutter_notification_gateway.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every mascot but the tree has a generated small icon', () {
    for (final kind in MascotKind.values) {
      if (kind == MascotKind.fallback) continue;
      expect(
        FlutterNotificationGateway.mascotIcons,
        contains(kind.id),
        reason: 'run tool/mascot_icons.sh',
      );
      for (final d in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
        final f = 'android/app/src/main/res/drawable-$d/ic_stat_${kind.id}.png';
        expect(File(f).existsSync(), isTrue, reason: f);
      }
    }
  });

  test('the small icon follows the saved mascot', () async {
    SharedPreferences.setMockInitialValues({});
    expect(
      await FlutterNotificationGateway.smallIconForMascot(),
      'ic_stat_ghina',
    );

    SharedPreferences.setMockInitialValues({'mascot.kind': 'hantu'});
    expect(
      await FlutterNotificationGateway.smallIconForMascot(),
      'ic_stat_hantu',
    );

    SharedPreferences.setMockInitialValues({'mascot.kind': 'pohon'});
    expect(
      await FlutterNotificationGateway.smallIconForMascot(),
      'ic_stat_ghina',
    );

    SharedPreferences.setMockInitialValues({'mascot.kind': 'unknown'});
    expect(
      await FlutterNotificationGateway.smallIconForMascot(),
      'ic_stat_ghina',
    );
  });
}
