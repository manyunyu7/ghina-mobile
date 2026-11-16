import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/diagnostics/error_log.dart';
import '../data/widgets/kantor_widget_sync.dart';
import '../di/kantor_providers.dart';
import '../presentation/design_system/design_system.dart';
import '../presentation/features/kantor/kantor_data.dart';
import '../presentation/features/kantor/session/kantor_snapshot_store.dart';
import '../presentation/features/settings/pages/appearance_page.dart';
import '../presentation/features/settings/pages/error_log_page.dart';
import '../presentation/features/settings/pages/mascot_picker_page.dart';
import '../presentation/features/settings/widgets/error_card.dart';
import '../presentation/state/appearance_provider.dart';
import '../presentation/state/mascot_kind_provider.dart';
import 'kantor_routes.dart';
import 'ravel_notifications.dart';

/// Set once the first-run "Pilih maskotmu" sheet was answered (a pick or
/// "Nanti saja"), so it shows only once, existing installs included.
const ravelMascotChosenKey = 'ravel.mascot_chosen';

final ravelRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/kantor',
    routes: [
      ...kantorRoutes,
      GoRoute(path: '/diagnostics', builder: (_, _) => const ErrorLogPage()),
      GoRoute(
        path: '/settings/mascot',
        builder: (_, _) => const MascotPickerPage(),
      ),
      GoRoute(
        path: '/settings/appearance',
        builder: (_, _) => const AppearancePage(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Ravel')),
      body: Center(
        child: TextButton(
          onPressed: () => context.go('/kantor'),
          child: const Text('Buka Kantor'),
        ),
      ),
    ),
  );
  ref.onDispose(router.dispose);
  return router;
});

class RavelApp extends ConsumerWidget {
  const RavelApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(ravelRouterProvider);
    final look = ref.watch(appearanceProvider);
    ErrorLog.instance.routeProbe = () =>
        router.routerDelegate.currentConfiguration.uri.toString();
    openErrorLog = () => router.push('/diagnostics');
    return MaterialApp.router(
      title: 'Ravel',
      debugShowCheckedModeBanner: false,
      theme: GhinaTheme.light(accent: look.accent, style: look.style),
      darkTheme: GhinaTheme.dark(accent: look.accent, style: look.style),
      themeMode: look.mode,
      locale: const Locale('id', 'ID'),
      supportedLocales: const [Locale('id', 'ID'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: router,
      // Like GhinaApp: the chosen mascot reaches every MascotView (sheets too).
      builder: (context, child) => AppearanceScope(
        child: MascotKindScope(
          child: _RavelServices(
            router: router,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

class _RavelServices extends ConsumerStatefulWidget {
  const _RavelServices({required this.router, required this.child});
  final GoRouter router;
  final Widget child;

  @override
  ConsumerState<_RavelServices> createState() => _RavelServicesState();
}

class _RavelServicesState extends ConsumerState<_RavelServices> {
  StreamSubscription<String>? _taps;
  Set<String>? _seen;
  bool _welcome = false;
  ChildBackButtonDispatcher? _welcomeBack;

  void _open(String route) {
    if (!mounted || !(route == '/kantor' || route.startsWith('/kantor/'))) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.router.push(route);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _openNotice(String payload) async {
    final target = RavelNotifications.targetOf(payload);
    if (target == null) return;
    try {
      final current = await ref.read(kantorConfigProvider.future);
      if (!mounted) return;
      _open(current.baseUrl == target.baseUrl ? target.route : '/kantor');
    } catch (_) {
      _open('/kantor');
    }
  }

  @override
  void initState() {
    super.initState();
    _taps = RavelNotifications.routes.listen(_openNotice);
    final launch = RavelNotifications.takeLaunchRoute();
    if (launch != null) unawaited(_openNotice(launch));
    ref.listenManual(kantorConfigProvider, (_, _) => _seen = null);
    unawaited(RavelNotifications.requestPermission());
    // after the first frame: start reading the offline snapshot from disk
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(kantorSnapshotStoreProvider);
      unawaited(_welcomeMascot());
    });
  }

  /// Offers the mascot picker once, over whatever screen opened first.
  Future<void> _welcomeMascot() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted || (prefs.getBool(ravelMascotChosenKey) ?? false)) return;
      // Android back while the layer is up means "Nanti saja".
      _welcomeBack =
          ChildBackButtonDispatcher(widget.router.backButtonDispatcher)
            ..addCallback(_welcomeBackPressed)
            ..takePriority();
      setState(() => _welcome = true);
    } catch (_) {}
  }

  Future<bool> _welcomeBackPressed() async {
    _finishWelcome();
    return true;
  }

  void _finishWelcome() {
    if (!_welcome) return;
    _dropWelcomeBack();
    setState(() => _welcome = false);
    unawaited(
      SharedPreferences.getInstance().then(
        (p) => p.setBool(ravelMascotChosenKey, true),
      ),
    );
  }

  void _dropWelcomeBack() {
    final back = _welcomeBack;
    if (back == null) return;
    _welcomeBack = null;
    back.removeCallback(_welcomeBackPressed);
    widget.router.backButtonDispatcher.forget(back);
  }

  @override
  Widget build(BuildContext context) {
    // Fresh state from the Kantor daemon only; no Ghina login, poller or reminders.
    ref.listen(kantorStateProvider, (_, next) {
      final state = next.value;
      if (state == null || next.isLoading || next.hasError) return;
      final items = (state['inbox'] as List? ?? []).whereType<Map>();
      final current = <String>{};
      for (final item in items) {
        final id = item['id']?.toString();
        if (id == null || item['held'] != true) continue;
        current.add(id);
        if (_seen != null && !_seen!.contains(id)) {
          final config = ref.read(kantorConfigProvider).value;
          if (config != null && config.ready) {
            unawaited(
              RavelNotifications.showInbox(
                item,
                baseUrl: config.baseUrl,
                label: RavelNotifications.inboxLabel(state, item),
              ),
            );
          }
        }
      }
      _seen = current;
    });
    // Always a Stack, so showing the layer never rebuilds the navigator.
    return Stack(
      children: [
        KantorWidgetSync(onOpen: _open, child: widget.child),
        if (_welcome)
          Positioned.fill(child: MascotWelcomeLayer(onDone: _finishWelcome)),
      ],
    );
  }

  @override
  void dispose() {
    _taps?.cancel();
    _dropWelcomeBack();
    super.dispose();
  }
}
