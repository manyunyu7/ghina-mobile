// Local Android fixture only. Uses actual chat attachment + permanent downloader.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ghina/data/platform/kantor_downloads.dart';
import 'package:ghina/di/kantor_providers.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/pratinjau/pratinjau_downloads.dart';
import 'package:ghina/presentation/features/kantor/session/attachment_files.dart';
import 'package:ghina/presentation/features/kantor/session/attachment_model.dart';
import 'package:ghina/presentation/features/kantor/session/attachment_views.dart';

final api = KantorApi(
  const KantorConfig(baseUrl: 'http://10.0.2.2:18376', token: 'fixture-only'),
);
const background = KantorAttachment(
  id: 'fixture-chat',
  name: 'Chat-background-49.bin',
  mime: 'application/octet-stream',
  size: 8388608,
  mine: false,
  agent: 'Agen uji',
  caption: '',
  at: '',
);
const retryFile = KantorAttachment(
  id: 'fixture-retry',
  name: 'Chat-retry-49.bin',
  mime: 'application/octet-stream',
  size: 262144,
  mine: false,
  agent: 'Agen uji',
  caption: '',
  at: '',
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      theme: GhinaTheme.light(),
      home: Scaffold(
        appBar: AppBar(title: const Text('Download lampiran chat')),
        body: Column(
          children: [
            const KantorDownloadStrip(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [AttachmentBubble(item: background, api: api)],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  unawaited(probe());
}

Future<KantorDownload> wait(int id, bool Function(KantorDownload) done) async {
  for (var i = 0; i < 45; i++) {
    final row = (await KantorDownloads.instance.list()).firstWhere(
      (r) => r.id == id,
    );
    if (done(row)) return row;
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  throw StateError('timeout');
}

Future<void> probe() async {
  try {
    final rows = await KantorDownloads.instance.list();
    if (rows.any((r) => r.name == background.name)) {
      final finished = rows.firstWhere((r) => r.name == background.name);
      if (!finished.complete) {
        throw StateError('background not complete on reopen');
      }
      debugPrint('CHAT_PROBE RESTORED_COMPLETE ${finished.received}');
      final old = rows.firstWhere((r) => r.name == retryFile.name);
      if (old.status == 'failed') {
        await KantorDownloads.instance.action('retry', old.id);
        final next = (await KantorDownloads.instance.list()).firstWhere(
          (r) => r.name == retryFile.name,
        );
        if (next.id == old.id) throw StateError('retry identity');
        await wait(next.id, (r) => r.received > 0 && r.status != 'failed');
        debugPrint('CHAT_PROBE PERSISTED_AUTH_RETRY_PASS');
      }
      return;
    }
    final retry = await saveAttachmentToDownloads(api, retryFile);
    final failed = await wait(retry, (r) => r.status == 'failed');
    if (failed.reason != 404) {
      throw StateError('authorization or fixture failed');
    }
    debugPrint('CHAT_PROBE AUTHENTICATED_404_PASS');
    final id = await saveAttachmentToDownloads(api, background);
    if (await saveAttachmentToDownloads(api, background) != id) {
      throw StateError('duplicate');
    }
    await wait(id, (r) => r.active && r.received > 0);
    debugPrint('CHAT_PROBE BACKGROUND_READY $id');
  } catch (e) {
    debugPrint('CHAT_PROBE FAILED ${e.runtimeType}');
    rethrow;
  }
}
