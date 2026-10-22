import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/data/datasources/remote/api_client.dart';
import 'package:ghina/data/datasources/remote/token_store.dart';
import 'package:ghina/data/notifications/notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_notification_gateway.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond, {this.status = 200});
  final int status;
  final Map<String, Object?> Function(RequestOptions) respond;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(respond(options)),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late FakeNotificationGateway gateway;
  late _Adapter adapter;
  KantorNoticePoller make(
    Map<String, Object?> Function(RequestOptions) f, {
    int status = 200,
    DateTime Function()? now,
  }) {
    adapter = _Adapter(f, status: status);
    final dio = Dio(BaseOptions(baseUrl: 'http://x'))
      ..httpClientAdapter = adapter;
    return KantorNoticePoller(
      ApiClient(
        baseUrl: 'http://x',
        tokens: MemoryTokenStore()..token = 't',
        dio: dio,
      ),
      gateway,
      now: now,
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    gateway = FakeNotificationGateway();
  });

  test('first poll stores the cursor and shows nothing', () async {
    final p = make((_) => {'notices': [], 'cursor': 1000});
    expect(await p.poll(), 0);
    expect(adapter.requests.single.queryParameters.containsKey('after'), false);
    expect(
      (await SharedPreferences.getInstance()).getInt(
        KantorNoticePoller.cursorKey,
      ),
      1000,
    );
    expect(gateway.shown, isEmpty);
  });

  test('shows notices on the Kantor channel with a /kantor route', () async {
    SharedPreferences.setMockInitialValues({KantorNoticePoller.cursorKey: 5});
    final p = make(
      (_) => {
        'notices': [
          {
            'id': 'n1',
            'title': 'Izin diminta',
            'body': 'Agen X',
            'office': 'a',
            'event': 'permission',
            'sid': 's1',
          },
        ],
        'cursor': 9,
      },
    );
    expect(await p.poll(), 1);
    expect(adapter.requests.single.queryParameters['after'], 5);
    final n = gateway.shown.single;
    expect(n.channel, NotificationChannelKind.kantor);
    expect(n.title, 'Izin diminta');
    expect(notificationRouteOf(n.payload), '/kantor/o/a/s/s1');
    expect(
      (await SharedPreferences.getInstance()).getInt(
        KantorNoticePoller.cursorKey,
      ),
      9,
    );
  });

  test('routes: no office, meeting, office without sid', () {
    String r(KantorNotice n) => notificationRouteOf(n.payload)!;
    expect(r(const KantorNotice(id: 'a', title: 't', body: '')), '/kantor');
    expect(
      r(
        const KantorNotice(
          id: 'a',
          title: 't',
          body: '',
          office: 'o',
          event: 'meeting_done',
        ),
      ),
      '/kantor/o/o?tab=rapat',
    );
    expect(
      r(const KantorNotice(id: 'a', title: 't', body: '', office: 'o')),
      '/kantor',
    );
  });

  test('ids avoid the prayer block and are stable', () {
    expect(KantorNoticePoller.idFor('a'), KantorNoticePoller.idFor('a'));
  });

  test('404: logs once, then skips polls with a growing backoff', () async {
    var clock = DateTime(2026, 1, 1);
    final p = make((_) => {}, status: 404, now: () => clock);
    final logs = <String>[];
    final old = debugPrint;
    debugPrint = (m, {wrapWidth}) => logs.add(m ?? '');
    addTearDown(() => debugPrint = old);

    expect(await p.poll(), 0);
    expect(adapter.requests, hasLength(1));
    // 20 s later (the poll timer): no request, no log.
    clock = clock.add(const Duration(seconds: 20));
    expect(await p.poll(), 0);
    expect(adapter.requests, hasLength(1));
    // After the first backoff it tries again, quietly, and waits twice as long.
    clock = clock.add(KantorNoticePoller.missingBackoffStart);
    await p.poll();
    expect(adapter.requests, hasLength(2));
    clock = clock.add(KantorNoticePoller.missingBackoffStart);
    await p.poll();
    expect(adapter.requests, hasLength(2));
    expect(logs.where((l) => l.contains('Kantor poll')), hasLength(1));
  });
}
