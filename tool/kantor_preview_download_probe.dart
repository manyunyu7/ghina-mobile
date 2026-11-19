// Android visual probe using the real agent Pratinjau tab and local fixtures.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ghina/di/kantor_providers.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/session/session_pratinjau_tab.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final api = KantorApi(
    const KantorConfig(baseUrl: 'http://10.0.2.2:18376', token: 'fixture-only'),
  );
  final item = PratinjauItem.fromJson({
    'id': 'preview-fixture',
    'office': 'fixture',
    'title': 'Hasil pratinjau agen',
    'jenis': 'info',
    'version': 1,
    'fromName': 'Agen uji',
    'files': [
      {
        'id': 'f1',
        'name': 'Pratinjau-contoh.bin',
        'mime': 'application/octet-stream',
        'kind': 'other',
        'size': 8388608,
        'url': '/pv/fixture/key/preview-ui.bin',
      },
    ],
  });
  runApp(
    ProviderScope(
      overrides: [
        kantorApiProvider.overrideWith((ref) => api),
        kantorPratinjauSessionProvider(
          ('fixture', 'probe'),
        ).overrideWith((ref) async => PratinjauFeed(items: [item], counts: {})),
      ],
      child: MaterialApp(
        theme: GhinaTheme.light(),
        home: Scaffold(
          appBar: AppBar(title: const Text('Pratinjau agen')),
          body: const KantorSessionPratinjauTab(
            officeId: 'fixture',
            sid: 'probe',
            role: null,
            actions: null,
          ),
        ),
      ),
    ),
  );
}
