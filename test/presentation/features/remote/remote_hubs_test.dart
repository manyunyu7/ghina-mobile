import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/data/datasources/remote/kantor_api.dart';
import 'package:ghina/presentation/features/remote/input/remote_input.dart';
import 'package:ghina/presentation/features/remote/remote_hubs.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _unreachable = KantorException(KantorFailure.unreachable, 'x');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('hub list', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test(
      'primary first, extras validated and deduped, last good first',
      () async {
        final list = RemoteHubList();
        const primary = 'http://kantor.example:8787/';
        await list.setExtras(primary, [
          'https://hub-a.example',
          'ftp://nope',
          'https://hub-a.example/',
          'http://kantor.example:8787',
          '',
          'https://hub-b.example:8443/path',
        ]);
        expect(await list.extras(primary), [
          'https://hub-a.example',
          'https://hub-b.example:8443',
        ]);
        expect(await list.ordered(primary), [
          'http://kantor.example:8787',
          'https://hub-a.example',
          'https://hub-b.example:8443',
        ]);
        await list.remember(primary, 'https://hub-b.example:8443');
        expect(
          (await list.ordered(primary)).first,
          'https://hub-b.example:8443',
        );
      },
    );
  });

  group('hub client', () {
    RemoteHubClient client(List<String> worked) => RemoteHubClient(
      id: 'http://a',
      urls: const ['http://a', 'http://b', 'http://c'],
      token: 'kcview_x',
      onWorking: worked.add,
    );

    test(
      'falls over unreachable hubs and sticks to the one that works',
      () async {
        final worked = <String>[];
        final c = client(worked);
        final tried = <String>[];
        final r = await c.run((api) async {
          tried.add(api.config.baseUrl);
          if (api.config.baseUrl != 'http://c') throw _unreachable;
          return 42;
        });
        expect(r, 42);
        expect(tried, ['http://a', 'http://b', 'http://c']);
        expect(worked, ['http://c']);
        expect(c.current.config.baseUrl, 'http://c');
        expect(c.current.config.token, 'kcview_x');
        // next call starts at the working hub
        tried.clear();
        await c.run((api) async => tried.add(api.config.baseUrl));
        expect(tried, ['http://c']);
      },
    );

    test('auth errors are not retried on other hubs', () async {
      final c = client([]);
      var calls = 0;
      await expectLater(
        c.run((api) async {
          calls++;
          throw const KantorException(KantorFailure.unauthorized, 'no');
        }),
        throwsA(isA<KantorException>()),
      );
      expect(calls, 1);
    });

    test('all unreachable → unreachable', () async {
      final c = client([]);
      await expectLater(
        c.run<int>((_) async => throw _unreachable),
        throwsA(
          isA<KantorException>().having(
            (e) => e.kind,
            'kind',
            KantorFailure.unreachable,
          ),
        ),
      );
    });
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
