import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/ravel_app.dart';
import 'app/ravel_notifications.dart';
import 'core/formatters.dart';
import 'data/diagnostics/error_log.dart';
import 'data/platform/stt_speech_transcriber.dart';
import 'presentation/state/platform/platform_providers.dart';
import 'di/kantor_providers.dart';
import 'presentation/features/settings/widgets/error_card.dart';
import 'presentation/state/appearance_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorLog.install();
  ErrorWidget.builder = ghinaErrorWidgetBuilder;
  await ErrorLog.instance.load();
  await Fmt.initFormatting();
  final appearance = await preloadAppearance();
  await RavelNotifications.initialize();
  runApp(
    ProviderScope(
      overrides: [
        kantorOnlyProvider.overrideWithValue(true),
        speechTranscriberProvider.overrideWith((ref) {
          final speech = SttSpeechTranscriber(useBluetooth: false);
          ref.onDispose(speech.dispose);
          return speech;
        }),
        appearanceInitialProvider.overrideWithValue(appearance),
      ],
      child: const RavelApp(),
    ),
  );
}
