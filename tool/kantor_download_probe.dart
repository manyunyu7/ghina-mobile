// Android-only manual integration probe. See docs/ravel-downloads.md.
// Uses an isolated emulator and a local fixture server; never owner credentials.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ghina/data/platform/kantor_downloads.dart';
import 'package:ghina/presentation/features/kantor/pratinjau/pratinjau_downloads.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: KantorDownloadsPage()));
  unawaited(probe());
}

Future<void> probe() async {
  const bridge = KantorDownloads.instance;
  const run = String.fromEnvironment('DOWNLOAD_PROBE_RUN', defaultValue: '2');
  const backgroundName = 'background-test-$run.bin';
  try {
    final restored = await bridge.list();
    if (restored.any((r) => r.name == backgroundName)) {
      debugPrint(
        'DOWNLOAD_PROBE RESTORED ${restored.map((r) => '${r.name}:${r.status}:${r.received}').join(',')}',
      );
      return;
    }
    Future<int> enqueue(String name) => bridge.enqueue(
      url: Uri.parse('http://10.0.2.2:18376/pv/fixture/key/$name'),
      name: name,
      mime: 'application/octet-stream',
      description: 'Pengujian lokal Ravel',
    );
    Future<KantorDownload> wait(
      int id,
      bool Function(KantorDownload) done,
    ) async {
      for (var n = 0; n < 45; n++) {
        final row = (await bridge.list()).firstWhere((r) => r.id == id);
        if (done(row)) return row;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      throw StateError('status timeout');
    }

    final cancelled = await enqueue('cancel-test.bin');
    await bridge.action('cancel', cancelled);
    await wait(cancelled, (r) => r.status == 'cancelled');
    debugPrint('DOWNLOAD_PROBE CANCEL_PASS');
    final bad = await enqueue('missing-test.bin');
    await wait(bad, (r) => r.status == 'failed');
    await bridge.action('retry', bad);
    final retry = (await bridge.list()).firstWhere(
      (r) => r.name == 'missing-test.bin',
    );
    if (retry.id == bad) throw StateError('retry must create a fresh transfer');
    await wait(retry.id, (r) => r.status == 'failed');
    debugPrint('DOWNLOAD_PROBE FAILURE_RETRY_PASS');
    final background = await enqueue(backgroundName);
    final same = await enqueue(backgroundName);
    if (same != background) throw StateError('duplicate transfer');
    debugPrint('DOWNLOAD_PROBE DEDUP_PASS');
    await wait(background, (r) => r.received > 0 && r.active);
    debugPrint('DOWNLOAD_PROBE BACKGROUND_READY $background');
  } catch (e) {
    debugPrint('DOWNLOAD_PROBE FAILED ${e.runtimeType}');
    rethrow;
  }
}
