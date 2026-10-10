import 'dart:async';

import 'package:ghina/core/failure.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/repositories/repositories.dart';

/// In-memory Dreams repositories (use-case and widget tests). Invented data
/// only: "Trip contoh ke Kota Sample", "Mimpi contoh".
class _Store<T> {
  _Store(this.idOf);
  final String Function(T) idOf;
  final items = <String, T>{};
  final _changes = StreamController<void>.broadcast();

  void put(T v) {
    items[idOf(v)] = v;
    _changes.add(null);
  }

  void remove(String id) {
    items.remove(id);
    _changes.add(null);
  }

  Stream<R> watch<R>(R Function() read) => Stream<R>.multi((c) {
    c.add(read());
    final sub = _changes.stream.listen((_) => c.add(read()));
    c.onCancel = sub.cancel;
  });
}

/// Dreams in list order; a delete also drops the dream's steps and metrics
/// (like the real repository's cascade).
class FakeDreamRepository implements DreamRepository {
  FakeDreamRepository({this.steps, this.metrics});

  final FakeDreamStepRepository? steps;
  final FakeDreamMetricRepository? metrics;
  final s = _Store<Dream>((d) => d.id);
  final deleted = <String>[];

  List<Dream> get _sorted => s.items.values.toList()
    ..sort((a, b) {
      final c = a.sortOrder.compareTo(b.sortOrder);
      if (c != 0) return c;
      if (a.targetDate == null && b.targetDate == null) {
        return a.title.compareTo(b.title);
      }
      if (a.targetDate == null) return 1;
      if (b.targetDate == null) return -1;
      return a.targetDate!.compareTo(b.targetDate!);
    });

  @override
  Stream<List<Dream>> watchAll() => s.watch(() => _sorted);

  @override
  Future<List<Dream>> getAll() async => _sorted;

  @override
  Stream<Dream?> watchById(String id) => s.watch(() => s.items[id]);

  @override
  Future<Dream?> getById(String id) async => s.items[id];

  @override
  Future<void> save(Dream dream) async => s.put(dream);

  @override
  Future<void> delete(String id) async {
    s.remove(id);
    deleted.add(id);
    steps?.s.items.removeWhere((_, x) => x.dreamId == id);
    metrics?.s.items.removeWhere((_, x) => x.dreamId == id);
  }
}

class FakeDreamStepRepository implements DreamStepRepository {
  final s = _Store<DreamStep>((x) => x.id);

  List<DreamStep> _of(String dreamId) =>
      s.items.values.where((x) => x.dreamId == dreamId).toList()..sort((a, b) {
        final c = a.sortOrder.compareTo(b.sortOrder);
        return c != 0 ? c : a.id.compareTo(b.id);
      });

  @override
  Stream<List<DreamStep>> watchForDream(String dreamId) =>
      s.watch(() => _of(dreamId));

  @override
  Future<List<DreamStep>> getForDream(String dreamId) async => _of(dreamId);

  @override
  Future<DreamStep?> getById(String id) async => s.items[id];

  @override
  Future<void> save(DreamStep step) async => s.put(step);

  @override
  Future<void> delete(String id) async => s.remove(id);
}

class FakeDreamMetricRepository implements DreamMetricRepository {
  final s = _Store<DreamMetric>((x) => x.id);

  List<DreamMetric> _of(String dreamId) =>
      s.items.values.where((x) => x.dreamId == dreamId).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  @override
  Stream<List<DreamMetric>> watchForDream(String dreamId) =>
      s.watch(() => _of(dreamId));

  @override
  Future<List<DreamMetric>> getForDream(String dreamId) async => _of(dreamId);

  @override
  Future<DreamMetric?> getById(String id) async => s.items[id];

  @override
  Future<void> save(DreamMetric metric) async => s.put(metric);

  @override
  Future<void> delete(String id) async => s.remove(id);
}

class FakeDreamCategoryRepository implements DreamCategoryRepository {
  final s = _Store<DreamCategory>((x) => x.id);

  List<DreamCategory> get _sorted => s.items.values.toList()
    ..sort((a, b) {
      final c = a.sortOrder.compareTo(b.sortOrder);
      return c != 0 ? c : a.label.compareTo(b.label);
    });

  @override
  Stream<List<DreamCategory>> watchAll() => s.watch(() => _sorted);

  @override
  Future<List<DreamCategory>> getAll() async => _sorted;

  @override
  Future<DreamCategory?> getById(String id) async => s.items[id];

  @override
  Future<void> save(DreamCategory category) async => s.put(category);

  @override
  Future<void> delete(String id) async => s.remove(id);
}

class FakeDreamFieldRepository implements DreamFieldRepository {
  final s = _Store<DreamFieldDef>((x) => x.id);

  List<DreamFieldDef> get _sorted => s.items.values.toList()
    ..sort((a, b) {
      final c = a.sortOrder.compareTo(b.sortOrder);
      return c != 0 ? c : a.label.compareTo(b.label);
    });

  @override
  Stream<List<DreamFieldDef>> watchAll() => s.watch(() => _sorted);

  @override
  Future<List<DreamFieldDef>> getAll() async => _sorted;

  @override
  Future<DreamFieldDef?> getById(String id) async => s.items[id];

  @override
  Future<void> save(DreamFieldDef def) async => s.put(def);

  @override
  Future<void> delete(String id) async => s.remove(id);
}

/// The server side: canned answers, and a record of what was asked.
class FakeDreamOnlineRepository implements DreamOnlineRepository {
  FakeDreamOnlineRepository({
    this.summaryValue,
    this.detailValue,
    this.manualValue,
    this.failure,
  });

  DreamSummary? summaryValue;
  DreamDetail? detailValue;
  ManualValueResult? manualValue;

  /// When set, every call fails with it (offline, unauthorized, …).
  Failure? failure;
  final calls = <String>[];

  void _check() {
    if (failure != null) throw failure!;
  }

  @override
  Future<DreamSummary> summary({String? tz}) async {
    calls.add('summary:${tz ?? '-'}');
    _check();
    return summaryValue ?? (throw const UnknownFailure('no summary'));
  }

  @override
  Future<DreamDetail> fetch(String id, {String? tz}) async {
    calls.add('fetch:$id');
    _check();
    return detailValue ?? (throw const NotFoundFailure());
  }

  @override
  Future<ManualValueResult> recordManualValue(
    String dreamId,
    String metricId,
    double value, {
    DateTime? at,
  }) async {
    calls.add('value:$dreamId/$metricId=$value');
    _check();
    return manualValue ?? (throw const UnknownFailure('no value'));
  }
}
