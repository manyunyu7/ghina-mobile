import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../presentation/design_system/design_system.dart';
import '../presentation/features/shell/app_shortcut_listener.dart';
import '../presentation/features/shell/notification_navigation.dart';
import '../presentation/state/appearance_provider.dart';
import '../presentation/state/balance_privacy_provider.dart';
import '../presentation/state/mascot_kind_provider.dart';
import '../presentation/state/session_controller.dart';
import 'router.dart';

/// Locations where a tapped reminder / launcher shortcut must wait (auth / splash / onboarding).
const _notReadyPaths = {'/splash', '/login', '/register', '/onboarding'};

class GhinaApp extends ConsumerWidget {
  const GhinaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final look = ref.watch(appearanceProvider);
    return MaterialApp.router(
      title: 'Ghina',
      debugShowCheckedModeBanner: false,
      theme: GhinaTheme.light(accent: look.accent, style: look.style),
      darkTheme: GhinaTheme.dark(accent: look.accent, style: look.style),
      themeMode: look.mode,
      locale: const Locale('id', 'ID'),
      supportedLocales: const [Locale('id', 'ID'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: router,
      // Reminder taps open `/tasks/<id>` (cold start included: waits until
      // signed in and past splash/onboarding).
      // Balance privacy wraps the navigator so dialogs/sheets are masked too;
      // the chosen mascot likewise reaches every MascotView (sheets included),
      // and the chosen text size every Text.
      builder: (context, child) => AppearanceScope(
        child: MascotKindScope(
          child: BalancePrivacyScope(
            child: NotificationRouteGate(
              router: router,
              canOpen: () =>
                  ref.read(sessionControllerProvider) is SignedIn &&
                  !_notReadyPaths.contains(
                    router.routerDelegate.currentConfiguration.uri.path,
                  ),
              // Launcher shortcuts (long-press the icon) use the same gate.
              child: AppShortcutListener(
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
