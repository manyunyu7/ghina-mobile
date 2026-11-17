import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/ravel_app.dart';
import 'app/ravel_notifications.dart';
import 'core/formatters.dart';
import 'data/diagnostics/dictation_log.dart';
import 'data/diagnostics/error_log.dart';
import 'data/platform/launcher_icon_bridge.dart';
import 'data/platform/stt_speech_transcriber.dart';
import 'presentation/state/platform/platform_providers.dart';
import 'di/kantor_providers.dart';
import 'di/prayer_reminder_providers.dart' show launcherIconProvider;
import 'presentation/features/settings/widgets/error_card.dart';
import 'presentation/state/appearance_provider.dart';
import 'presentation/state/mascot_kind_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorLog.install();
  ErrorWidget.builder = ghinaErrorWidgetBuilder;
  await ErrorLog.instance.load();
  await DictationLog.instance.load();
  await Fmt.initFormatting();
  final appearance = await preloadAppearance();
  final mascot = await preloadMascotKind();
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
        mascotKindInitialProvider.overrideWithValue(mascot),
        // The ravel manifest drops the mascot activity-aliases; the icon
        // stays ic_launcher_ravel, so never ask native to switch.
        launcherIconProvider.overrideWithValue(const NoopLauncherIcon()),
      ],
      child: const RavelApp(),
    ),
  );
}
