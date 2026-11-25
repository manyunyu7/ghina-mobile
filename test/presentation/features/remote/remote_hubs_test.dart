import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/data/datasources/remote/kantor_api.dart';
import 'package:ghina/presentation/features/remote/input/remote_input.dart';
import 'package:ghina/presentation/features/remote/remote_hubs.dart';
import 'package:ghina/presentation/features/remote/remote_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _unreachable = KantorException(KantorFailure.unreachable, 'x');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('hub store', () {
    late RemoteHubStore store;
    late MemoryRemoteSecrets secrets;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      secrets = MemoryRemoteSecrets();
      store = RemoteHubStore(secrets: secrets);
    });

    test('adds the Kantor as first hub and migrates its old token', () async {
      await secrets.write(
        RemoteHubStore.legacyViewerKey('http://kantor.example:8787'),
        'kcview_old',
      );
      final hubs = await store.hubs(kantorUrl: 'http://kantor.example:8787/');
      expect(hubs.single.kind, RemoteHubKind.kantor);
      expect(hubs.single.url, 'http://kantor.example:8787');
      expect(await store.viewerToken(hubs.single.id), 'kcview_old');
      // idempotent
      expect(
        await store.hubs(kantorUrl: 'http://kantor.example:8787'),
        hasLength(1),
      );
    });

    test('tokens are per hub; relay owner token kept per hub', () async {
      const relay = RemoteHub(
        id: 'r1',
        name: 'VPS',
        url: 'https://relay.example',
        kind: RemoteHubKind.relay,
      );
      const kantor = RemoteHub(
        id: 'k1',
        name: 'Kantor',
        url: 'http://kantor.example:8787',
        kind: RemoteHubKind.kantor,
      );
      await store.save([kantor, relay]);
      await store.setViewerToken('k1', 'kcview_k');
      await store.setOwnerToken('r1', ' kcowner_r ');
      expect(await store.viewerToken('k1'), 'kcview_k');
      expect(await store.viewerToken('r1'), isNull);
      expect(await store.ownerToken('r1'), 'kcowner_r');
      await store.remove('r1');
      expect(await store.ownerToken('r1'), isNull);
      expect((await store.hubs()).map((h) => h.id), ['k1']);
    });

    test('try order: last working first, then list order', () {
      RemoteHub h(String id) => RemoteHub(
        id: id,
        name: id,
        url: 'https://$id.example',
        kind: RemoteHubKind.relay,
      );
      final list = [h('a'), h('b'), h('c')];
      expect(RemoteHubStore.tryOrder(list, 'c').map((x) => x.id), [
        'c',
        'a',
        'b',
      ]);
      expect(RemoteHubStore.tryOrder(list, null).map((x) => x.id), [
        'a',
        'b',
        'c',
      ]);
      expect(RemoteHubStore.parseUrl('ftp://x'), isNull);
      expect(
        RemoteHubStore.parseUrl('https://x.example/p'),
        'https://x.example',
      );
    });
  });

  group('hub client', () {
    RemoteHub h(String id) => RemoteHub(
      id: id,
      name: id,
      url: 'http://$id',
      kind: RemoteHubKind.relay,
    );
    RemoteHubClient client(List<String> worked, List<String> refused) =>
        RemoteHubClient(
          [
            RemoteHubConn(h('a'), 'kcview_a'),
            RemoteHubConn(h('b'), 'kcview_b'),
            RemoteHubConn(h('c'), 'kcview_c'),
          ],
          onWorking: (x) => worked.add(x.id),
          onUnauthorized: (x) => refused.add(x.id),
        );

    test(
      'skips unreachable and refusing hubs, each with its own token',
      () async {
        final worked = <String>[];
        final refused = <String>[];
        final c = client(worked, refused);
        final tried = <String>[];
        final r = await c.run((api) async {
          tried.add('${api.config.baseUrl} ${api.config.token}');
          if (api.config.baseUrl == 'http://a') throw _unreachable;
          if (api.config.baseUrl == 'http://b') {
            throw const KantorException(KantorFailure.unauthorized, 'no');
          }
          return 42;
        });
        expect(r, 42);
        expect(tried, [
          'http://a kcview_a',
          'http://b kcview_b',
          'http://c kcview_c',
        ]);
        expect(refused, ['b']);
        expect(worked, ['c']);
        expect(c.current.hub.id, 'c');
      },
    );

    test('all hubs refuse → needs pairing', () async {
      final refused = <String>[];
      final c = client([], refused);
      await expectLater(
        c.run<int>(
          (_) async =>
              throw const KantorException(KantorFailure.unauthorized, 'x'),
        ),
        throwsA(
          isA<RemoteHubsFailed>().having(
            (e) => e.needPairing.length,
            'needPairing',
            3,
          ),
        ),
      );
      expect(refused, ['a', 'b', 'c']);
    });

    test('other errors are not retried elsewhere', () async {
      final c = client([], []);
      var calls = 0;
      await expectLater(
        c.run((api) async {
          calls++;
          throw const KantorException(KantorFailure.server, 'boom');
        }),
        throwsA(isA<KantorException>()),
      );
      expect(calls, 1);
    });

    test('only() narrows to the hubs where a Mac was seen', () {
      final c = client([], []).only(['c', 'a']);
      expect(c.conns.map((x) => x.hub.id), ['a', 'c']);
      expect(client([], []).only(['zzz']).conns, hasLength(3));
    });

    test('a refused WebSocket upgrade is recognized', () {
      expect(
        RemoteHubClient.isAuthRefusal(
          const WebSocketException(
            "Connection to 'http://a/api/remote/ws' was not upgraded to "
            'websocket, HTTP status code: 403',
          ),
        ),
        isTrue,
      );
      expect(
        RemoteHubClient.isAuthRefusal(const WebSocketException('closed')),
        isFalse,
      );
    });
  });

  test('hosts from several hubs merge by machine, online hubs first', () {
    RemoteHub h(String id) => RemoteHub(
      id: id,
      name: id,
      url: 'http://$id',
      kind: RemoteHubKind.relay,
    );
    final merged = mergeHosts([
      (
        h('kantor'),
        const [
          RemoteHost(machine: 'mini', name: 'Mac mini', online: false),
          RemoteHost(machine: 'mbp', name: 'MacBook', online: true),
        ],
      ),
      (
        h('vps'),
        const [RemoteHost(machine: 'mini', name: 'Mac mini', online: true)],
      ),
    ]);
    expect(merged.map((e) => (e.host.machine, e.host.online)), [
      ('mini', true), // "Mac mini" sorts before "MacBook"
      ('mbp', true),
    ]);
    expect(merged.first.hubIds, ['vps', 'kantor']);
  });

  group('⌘V from the key bar', () {
    test('sends the phone clipboard first, then the shortcut', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.getData') {
              return {'text': 'dari HP'};
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final sent = <Map<String, dynamic>>[];
      final kb = RemoteKeyboardController()..send = sent.add;
      await kb.paste();
      expect(sent, [
        {'t': 'clip', 's': 'dari HP'},
        {
          't': 'key',
          'code': 'KeyV',
          'mods': ['meta'],
        },
      ]);
    });

    test('a session hook replaces the default clipboard read', () async {
      final order = <String>[];
      final kb = RemoteKeyboardController()
        ..send = ((m) => order.add(m['t'] as String))
        ..beforePaste = () async => order.add('hook');
      await kb.paste();
      expect(order, ['hook', 'key']);
    });
  });
}
