import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/formatters.dart';
import 'di/di.dart';
import 'presentation/state/balance_privacy_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Fmt.initFormatting();
  final privacy = await preloadBalancePrivacy();
  runApp(
    ProviderScope(
      overrides: [
        ...gameOverrides,
        ...reminderOverrides,
        balancePrivacyInitialProvider.overrideWithValue(privacy),
      ],
      child: const GhinaApp(),
    ),
  );
}
