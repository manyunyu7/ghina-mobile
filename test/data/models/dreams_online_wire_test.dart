// Online Dreams (docs/dreams.md → REST): the parsers over sample JSON shaped
// like the doc's examples (invented names only) and the repository over a fake
// Dio adapter. Unknown keys are ignored; a broken response is a failure, never
// a crash.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/failure.dart';
import 'package:ghina/data/datasources/remote/api_client.dart';
import 'package:ghina/data/datasources/remote/token_store.dart';
import 'package:ghina/data/models/dreams_online_wire.dart';
import 'package:ghina/data/repositories/dreams_online_repository_impl.dart';
import 'package:ghina/domain/entities/entities.dart';

const _summaryJson = {
  'date': '2026-10-10',
  'total': 6,
  'counts': {'active': 2, 'idea': 3, 'planned': 1},
  'open': 6,
  'estimatedCostOpen': 32500000,
  'stale': 0,
  'overdue': 0,
  'active': {
    'n': 2,
    'items': [
      {
        'id': 'id-9',
        'title': 'Bebas camilan 30 hari contoh',
        'pct': 47,
        'onTrack': true,
        'target': '2026-12-31',
        'precision': 'day',
      },
    ],
    'more': 0,
  },
  'nearest': {
    'n': 4,
    'items': [
      {
        'id': 'id-10',
        'title': 'Trip contoh ke Kota Sample',
        'target': '2027-01-31',
        'precision': 'month',
        'in': 113,
      },
    ],
    'more': 1,
  },
  'offTrack': {'n': 0, 'items': <Object>[], 'more': 0},
};

const _detailJson = {
  'dream': {
    'id': 'id-1',
    'title': 'Turun berat badan contoh',
    'emoji': '💪',
    'category': 'health',
    'status': 'active',
    'priority': 2,
    'horizon': 'this_year',
    'targetDate': '2027-06-30',
    'targetPrecision': 'quarter',
    'condition': 'Setelah jadwal kerja stabil',
    'why': 'Supaya lebih sehat.',
    'summary': null,
    'costEstimate': 3000000,
    'costNote': 'Perkiraan kasar',
    'progressManual': null,
    'startedAt': '2026-10-10',
    'completedAt': null,
    'noteId': null,
    'parentId': null,
    'tags': ['sehat', 'rutin'],
    'fields': {'sumber_contoh': 'daftar-1'},
    'links': {'taskIds': <Object>[], 'habitIds': <Object>[]},
    'sortOrder': 0,
    'createdAt': '2026-10-10T03:30:31.351Z',
    'updatedAt': '2026-10-10T03:30:31.351Z',
    'externalKey': 'contoh:berat-1',
    'progress': {
      'pct': 38,
      'onTrack': true,
      'projectedDate': '2026-12-03',
      'metricCount': 2,
      'stepsDone': 1,
      'stepsTotal': 3,
    },
    'stale': false,
    'overdue': false,
    'effectiveCost': 3000000,
    'lastActivityAt': '2026-10-10T03:30:31.358Z',
    'reviewReasons': <Object>[],
    'cost': {
      'estimate': 3000000,
      'stepsTotal': 600000,
      'stepsDone': 100000,
      'stepsRemaining': 500000,
      'stepsWithCost': 2,
      'diff': 2400000,
      'effective': 3000000,
    },
    'steps': [
      {
        'id': 'id-2',
        'dreamId': 'id-1',
        'title': 'Capai 88 kg',
        'notes': null,
        'done': true,
        'doneAt': '2026-10-10T03:30:31.356Z',
        'dueDate': null,
        'cost': 100000,
        'reward': 'Sepatu lari contoh',
        'metricRef': 'id-3',
        'atValue': 88,
        'sortOrder': 0,
        'createdAt': '2026-10-10T03:30:31.354Z',
        'updatedAt': '2026-10-10T03:30:31.358Z',
      },
      {
        'id': 'id-4',
        'dreamId': 'id-1',
        'title': 'Capai 80 kg',
        'notes': null,
        'done': false,
        'doneAt': null,
        'dueDate': null,
        'cost': 500000,
        'reward': null,
        'metricRef': 'id-3',
        'atValue': 80,
        'sortOrder': 1,
        'createdAt': '2026-10-10T03:30:31.355Z',
        'updatedAt': '2026-10-10T03:30:31.355Z',
      },
    ],
    'metrics': [
      {
        'id': 'id-3',
        'dreamId': 'id-1',
        'label': 'Berat contoh',
        'source': 'weight',
        'sourceRef': null,
        'direction': 'down',
        'unit': 'kg',
        'startValue': 90,
        'startDate': null,
        'targetValue': 80,
        'targetDate': '2027-06-30',
        'manualValue': null,
        'manualAt': null,
        'sortOrder': 0,
        'createdAt': '2026-10-10T03:30:31.353Z',
        'updatedAt': '2026-10-10T03:30:31.353Z',
        'currentValue': 86.4,
        'currentAt': '2026-10-10T03:30:31.224Z',
        'progressPct': 36,
        'onTrack': true,
        'projectedDate': '2026-12-03',
        'unavailable': null,
        'history': [
          {'at': '2026-10-04T03:30:31.224Z', 'value': 87.1},
          {'at': '2026-10-07T03:30:31.224Z', 'value': 86.8},
          {'at': '2026-10-10T03:30:31.224Z', 'value': 86.4},
        ],
      },
    ],
    'note': null,
    'parent': null,
    'children': <Object>[],
    'linkedTasks': <Object>[],
    'linkedHabits': <Object>[],
  },
};

const _valueJson = {
  'metric': {
    'id': 'id-7',
    'dreamId': 'id-8',
    'label': 'Dana darurat contoh',
    'source': 'manual',
    'sourceRef': null,
    'direction': 'up',
    'unit': 'Rp',
    'startValue': 0,
    'startDate': null,
    'targetValue': 12000000,
    'targetDate': null,
    'manualValue': 4800000,
    'manualAt': '2026-10-10T03:30:32.445Z',
    'sortOrder': 0,
    'createdAt': '2026-10-10T03:30:31.380Z',
    'updatedAt': '2026-10-10T03:30:32.446Z',
    'currentValue': 4800000,
    'currentAt': '2026-10-10T03:30:32.445Z',
    'progressPct': 40,
    'onTrack': true,
    'projectedDate': '2027-03-13',
    'unavailable': null,
    'history': [
      {'at': '2026-08-31T03:30:31.385Z', 'value': 1000000},
      {'at': '2026-10-10T03:30:32.445Z', 'value': 4800000},
    ],
  },
  'progress': {'pct': 40, 'onTrack': true},
  'stepsCompleted': ['id-5'],
};

void main() {
  group('summary', () {
    test('counts, the cost of open dreams and the lists', () {
      final s = dreamSummaryFromWire(_summaryJson)!;
      expect(s.date, '2026-10-10');
      expect(s.counts, {'active': 2, 'idea': 3, 'planned': 1});
      expect(s.estimatedCostOpen, 32500000);
      expect(s.active.items.single.pct, 47);
      expect(s.active.items.single.onTrack, isTrue);
      final near = s.nearest.items.single;
      expect(near.inDays, 113);
      expect(near.precision, 'month');
      expect(s.nearest.more, 1);
      expect(s.offTrack.items, isEmpty);
    });

    test('unknown keys are ignored; no date means no summary', () {
      final s = dreamSummaryFromWire({..._summaryJson, 'baru': 1})!;
      expect(s.total, 6);
      expect(dreamSummaryFromWire({'total': 1}), isNull);
    });
  });

  group('detail', () {
    test('the dream, its steps and its metrics with the computed values', () {
      final d = dreamDetailFromWire(_detailJson)!;
      expect(d.dream.title, 'Turun berat badan contoh');
      expect(d.dream.status, DreamStatus.active);
      expect(d.dream.targetPrecision, TargetPrecision.quarter);
      expect(d.dream.fields, {'sumber_contoh': 'daftar-1'});
      expect(d.steps.map((s) => s.done), [true, false]);
      expect(d.steps.first.metricRef, 'id-3');

      final m = d.metrics.single;
      expect(m.metric.source, MetricSource.weight);
      expect(m.metric.effectiveDirection, MetricDirection.down);
      expect(m.reading.currentValue, 86.4);
      expect(m.reading.progressPct, 36);
      expect(m.reading.onTrack, isTrue);
      expect(m.reading.projectedDate, '2026-12-03');
      expect(m.reading.unavailable, isNull);
      expect(m.reading.history.map((h) => h.value), [87.1, 86.8, 86.4]);
    });

    test('progress and cost come from the response, not from local sums', () {
      final d = dreamDetailFromWire(_detailJson)!;
      expect(d.progress.pct, 38);
      expect(d.progress.stepsTotal, 3);
      expect(d.cost.estimate, 3000000);
      expect(d.cost.stepsTotal, 600000);
      expect(d.cost.diff, 2400000);
      expect(d.cost.effective, 3000000);
      expect(d.reviewReasons, isEmpty);
      expect(d.stale, isFalse);
    });

    test('unknown keys are ignored; an unknown metric source is skipped', () {
      final json = jsonDecode(jsonEncode(_detailJson)) as Map<String, dynamic>;
      final dream = json['dream'] as Map<String, dynamic>;
      dream['masa_depan'] = {'baru': true};
      (dream['metrics'] as List).add({
        'id': 'id-x',
        'dreamId': 'id-1',
        'label': 'Entah apa contoh',
        'source': 'sumber_baru',
        'targetValue': 5,
        'createdAt': '2026-10-10T00:00:00.000Z',
      });
      final d = dreamDetailFromWire(json)!;
      expect(d.dream.id, 'id-1');
      expect(d.metrics, hasLength(1));
    });

    test(
      'an unknown unavailable reason reads as no reason; a missing dream is null',
      () {
        final json =
            jsonDecode(jsonEncode(_detailJson)) as Map<String, dynamic>;
        ((json['dream'] as Map)['metrics'] as List).first['unavailable'] =
            'baru';
        expect(
          dreamDetailFromWire(json)!.metrics.single.reading.unavailable,
          isNull,
        );
        expect(dreamDetailFromWire({'dream': 'rusak'}), isNull);
        expect(dreamDetailFromWire(const {}), isNull);
      },
    );

    test('a metric with no data says so', () {
      final json = jsonDecode(jsonEncode(_detailJson)) as Map<String, dynamic>;
      final m = ((json['dream'] as Map)['metrics'] as List).first as Map;
      m['currentValue'] = null;
      m['progressPct'] = null;
      m['onTrack'] = null;
      m['unavailable'] = 'no_data';
      final view = dreamDetailFromWire(json)!.metrics.single;
      expect(view.reading.currentValue, isNull);
      expect(view.reading.unavailable, MetricUnavailable.noData);
    });
  });

  group('manual value', () {
    test('the recomputed metric and the steps it completed', () {
      final r = manualValueResultFromWire(_valueJson)!;
      expect(r.metric.reading.progressPct, 40);
      expect(r.metric.metric.manualValue, 4800000);
      expect(r.metric.reading.history, hasLength(2));
      expect(r.stepsCompleted, ['id-5']);
    });

    test('no metric is no result', () {
      expect(manualValueResultFromWire({'progress': {}}), isNull);
    });
  });

  group('repository over the server (fake Dio adapter)', () {
    test(
      'summary asks with the time zone; detail and the value route match the doc',
      () async {
        final adapter = _Adapter({
          'GET /api/mobile/dreams/summary': (200, _summaryJson),
          'GET /api/mobile/dreams/id-1': (200, _detailJson),
          'POST /api/mobile/dreams/id-8/metrics/id-7/value': (200, _valueJson),
        });
        final repo = _repo(adapter);

        final s = await repo.summary(tz: 'Asia/Jakarta');
        expect(s.total, 6);
        expect(adapter.requests.first.queryParameters, {'tz': 'Asia/Jakarta'});

        final d = await repo.fetch('id-1');
        expect(d.metrics.single.reading.progressPct, 36);

        final v = await repo.recordManualValue(
          'id-8',
          'id-7',
          4800000,
          at: DateTime.utc(2026, 10, 10, 3),
        );
        expect(v.stepsCompleted, ['id-5']);
        final sent = adapter.requests.last;
        expect(sent.data, {
          'value': 4800000.0,
          'at': '2026-10-10T03:00:00.000Z',
        });
      },
    );

    test(
      'a response without its core object is a failure, not a crash',
      () async {
        final adapter = _Adapter({
          'GET /api/mobile/dreams/summary': (200, {'nonsense': true}),
          'GET /api/mobile/dreams/id-1': (200, {'dream': 'rusak'}),
        });
        final repo = _repo(adapter);
        await expectLater(repo.summary(), throwsA(isA<UnknownFailure>()));
        await expectLater(repo.fetch('id-1'), throwsA(isA<UnknownFailure>()));
      },
    );

    test('an error answer becomes a failure', () async {
      final adapter = _Adapter({
        'GET /api/mobile/dreams/id-404': (404, {'error': 'Tidak ditemukan'}),
      });
      final repo = _repo(adapter);
      await expectLater(repo.fetch('id-404'), throwsA(isA<Failure>()));
    });
  });
}

ApiDreamOnlineRepository _repo(_Adapter adapter) {
  final client = ApiClient(baseUrl: 'https://x.test', tokens: _Tokens());
  client.dio.httpClientAdapter = adapter;
  return ApiDreamOnlineRepository(client);
}

class _Tokens implements TokenStore {
  @override
  Future<String?> readToken() async => 'tok';
  @override
  Future<void> writeToken(String? token) async {}
  @override
  Future<String?> readUser() async => null;
  @override
  Future<void> writeUser(String? userJson) async {}
  @override
  Future<void> clear() async {}
}

/// Answers requests from a route table (`METHOD /path` → status + JSON body).
class _Adapter implements HttpClientAdapter {
  _Adapter(this.routes);

  final Map<String, (int, Object?)> routes;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(o);
    final key = '${o.method} ${o.path}';
    final (status, body) = routes[key] ?? (404, {'error': 'not found: $key'});
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
