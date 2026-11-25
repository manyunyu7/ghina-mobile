import 'package:go_router/go_router.dart';

import '../presentation/features/kantor/pages/kantor_complex_page.dart';
import '../presentation/features/kantor/pages/kantor_settings_page.dart';
import '../presentation/features/kantor/wizard/kantor_wizard_page.dart';
import '../presentation/features/kantor/pages/kantor_shell_page.dart';
import '../presentation/features/kantor/session/kantor_session_page.dart';
import '../presentation/features/kantor/pratinjau/pratinjau_detail.dart';
import '../presentation/features/kantor/pratinjau/pratinjau_feed.dart';
import '../presentation/features/remote/remote_hosts_page.dart';
import '../presentation/features/kantor/sysmon/kantor_sysmon_page.dart';

/// Shared by Ghina and the standalone Ravel app.
final kantorRoutes = <RouteBase>[
  GoRoute(
    path: '/kantor',
    builder: (_, _) => const KantorComplexPage(),
    routes: [
      GoRoute(path: 'settings', builder: (_, _) => const KantorSettingsPage()),
      GoRoute(path: 'new', builder: (_, _) => const KantorWizardPage()),
      GoRoute(path: 'pc', builder: (_, _) => const KantorSysmonPage()),
      GoRoute(path: 'remote', builder: (_, _) => const RemoteHostsPage()),
      GoRoute(
        path: 'o/:office',
        builder: (_, s) => KantorShellPage(
          officeId: s.pathParameters['office']!,
          tab: s.uri.queryParameters['tab'],
        ),
        routes: [
          GoRoute(
            path: 's/:sid',
            builder: (_, s) => KantorSessionPage(
              officeId: s.pathParameters['office']!,
              sid: s.pathParameters['sid']!,
              tab: s.uri.queryParameters['tab'],
            ),
          ),
          GoRoute(
            path: 'pratinjau',
            builder: (_, s) =>
                KantorPratinjauPage(officeId: s.pathParameters['office']!),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, s) => KantorPratinjauDetailPage(
                  officeId: s.pathParameters['office']!,
                  itemId: s.pathParameters['id']!,
                  fileId: s.uri.queryParameters['f'],
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  ),
];
