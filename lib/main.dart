import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/formatters.dart';
import 'di/di.dart';
import 'presentation/state/appearance_provider.dart';
import 'presentation/state/balance_privacy_provider.dart';
import 'presentation/state/mascot_kind_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Fmt.initFormatting();
  final privacy = await preloadBalancePrivacy();
  final mascot = await preloadMascotKind();
  final appearance = await preloadAppearance();
  runApp(
    ProviderScope(
      overrides: [
        ...gameOverrides,
        ...reminderOverrides,
        balancePrivacyInitialProvider.overrideWithValue(privacy),
        mascotKindInitialProvider.overrideWithValue(mascot),
        appearanceInitialProvider.overrideWithValue(appearance),
      ],
      child: const GhinaApp(),
    ),
  );
}
