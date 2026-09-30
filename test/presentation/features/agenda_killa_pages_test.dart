// Smoke tests of the Pengingat, Kalender and Killa screens: in-memory
// repositories behind the real use cases / providers.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/clock.dart';
import 'package:ghina/di/core_providers.dart';
import 'package:ghina/di/killa_providers.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/repositories/repositories.dart';
import 'package:ghina/domain/services/killa_media_picker.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/calendar/pages/calendar_page.dart';
import 'package:ghina/presentation/features/killa/pages/killa_chat_page.dart';
import 'package:ghina/presentation/features/reminders/pages/reminders_page.dart';
import 'package:ghina/presentation/state/killa_access_provider.dart';
import 'package:ghina/presentation/state/session_controller.dart';

final _now = DateTime(2026, 10, 1, 12);

class _Store<T> {
  _Store(this.idOf);
  final String Function(T) idOf;
  final items = <String, T>{};
  final _c = StreamController<void>.broadcast();

  Stream<List<T>> watch() async* {
    yield items.values.toList();
    await for (final _ in _c.stream) {
      yield items.values.toList();
    }
  }

  void put(T v) {
    items[idOf(v)] = v;
    _c.add(null);
  }

  void remove(String id) {
    items.remove(id);
    _c.add(null);
  }
}

class _Reminders implements ReminderItemRepository {
  final s = _Store<ReminderItem>((r) => r.id);
  @override
  Stream<List<ReminderItem>> watchAll() => s.watch();
  @override
  Future<List<ReminderItem>> getAll() async => s.items.values.toList();
  @override
  Stream<ReminderItem?> watchById(String id) =>
      s.watch().map((_) => s.items[id]);
  @override
  Future<ReminderItem?> getById(String id) async => s.items[id];
  @override
  Future<void> save(ReminderItem r) async => s.put(r);
  @override
  Future<void> delete(String id) async => s.remove(id);
}

class _Events implements CalendarEventRepository {
  final s = _Store<CalendarEvent>((e) => e.id);
  @override
  Stream<List<CalendarEvent>> watchAll() => s.watch();
  @override
  Future<List<CalendarEvent>> getAll() async => s.items.values.toList();
  @override
  Stream<CalendarEvent?> watchById(String id) =>
      s.watch().map((_) => s.items[id]);
  @override
  Future<CalendarEvent?> getById(String id) async => s.items[id];
  @override
  Future<void> save(CalendarEvent e) async => s.put(e);
  @override
  Future<void> delete(String id) async => s.remove(id);
}

class _Killa implements KillaRepository {
  KillaException? error;
  final messages = <KillaMessage>[];
  String? storedModel;
  final modelPosts = <String>[];

  @override
  Future<KillaModelSetting> model() async {
    if (error case final e?) throw e;
    return KillaModelSetting(
      model: storedModel,
      options: const ['default', 'opus', 'sonnet', 'haiku'],
    );
  }

  @override
  Future<String?> setModel(String model) async {
    modelPosts.add(model);
    return storedModel = model == 'default' ? null : model;
  }

  @override
  Future<KillaMessagePage> chat({String? before, int limit = 50}) async {
    if (error case final e?) throw e;
    return KillaMessagePage(messages: messages);
  }

  @override
  Future<KillaSendResult> send({
    required String text,
    List<KillaOutgoingMedia> media = const [],
  }) async {
    final u = KillaMessage(
      id: 'u${messages.length}',
      role: KillaRole.user,
      body: text,
      createdAt: _now,
    );
    final a = KillaMessage(
      id: 'a${messages.length}',
      role: KillaRole.assistant,
      body: 'Siap, **${storedModel ?? 'default'}**!',
      model: storedModel,
      createdAt: _now.add(const Duration(seconds: 5)),
    );
    messages.addAll([u, a]);
    return KillaSendResult(userMessage: u, reply: a);
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sync implements SyncService {
  @override
  void start() {}
  @override
  void stop() {}
  @override
  Future<void> syncNow() async {}
  @override
  Stream<SyncStatus> watchStatus() => Stream.value(SyncStatus.initial);
  @override
  Future<void> resetLocalData() async {}
}

ReminderItem _rem(String id, DateTime due, {bool done = false}) => ReminderItem(
  id: id,
  title: 'Pengingat $id',
  dueAt: due,
  done: done,
  doneAt: done ? due : null,
  createdAt: _now,
  updatedAt: _now,
);

Future<void> _pump(
  WidgetTester tester,
  Widget page,
  List<Override> overrides,
) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        clockProvider.overrideWithValue(FixedClock(_now)),
        tickSourceProvider.overrideWithValue(() => Stream.value(_now)),
        syncServiceProvider.overrideWithValue(_Sync()),
        currentUserProvider.overrideWithValue(null),
        killaAccessStoreProvider.overrideWithValue(InMemoryKillaAccessStore()),
        ...overrides,
      ],
      child: MaterialApp(
        theme: GhinaTheme.light(),
        darkTheme: GhinaTheme.dark(),
        themeMode: ThemeMode.dark,
        home: page,
      ),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('reminders: Terlambat / Mendatang / Selesai groups', (t) async {
    final repo = _Reminders()
      ..s.put(_rem('lewat', _now.subtract(const Duration(hours: 3))))
      ..s.put(_rem('nanti', _now.add(const Duration(hours: 3))))
      ..s.put(
        _rem('beres', _now.subtract(const Duration(days: 1)), done: true),
      );
    await _pump(t, const RemindersPage(), [
      reminderItemRepositoryProvider.overrideWithValue(repo),
    ]);
    expect(find.text('Terlambat'), findsWidgets);
    expect(find.text('Mendatang'), findsOneWidget);
    expect(find.text('Selesai'), findsOneWidget);
    expect(find.text('Pengingat lewat'), findsOneWidget);
    expect(find.text('Pengingat nanti'), findsOneWidget);

    // Completing the overdue one-off moves it to "Selesai".
    await t.tap(find.byKey(const ValueKey('reminder-check-lewat')));
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(repo.s.items['lewat']!.done, isTrue);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('reminders: empty state invites to create one', (t) async {
    await _pump(t, const RemindersPage(), [
      reminderItemRepositoryProvider.overrideWithValue(_Reminders()),
    ]);
    expect(find.text('Belum ada pengingat'), findsOneWidget);
  });

  testWidgets('calendar: month grid with dots and the day agenda', (t) async {
    final events = _Events()
      ..s.put(
        CalendarEvent(
          id: 'e1',
          title: 'Rapat tim',
          startAt: DateTime(2026, 10, 1, 9),
          endAt: DateTime(2026, 10, 1, 10, 30),
          createdAt: _now,
          updatedAt: _now,
        ),
      )
      ..s.put(
        CalendarEvent(
          id: 'e2',
          title: 'Liburan',
          startAt: DateTime(2026, 10, 5),
          endAt: DateTime(2026, 10, 7),
          allDay: true,
          color: '#58CC02',
          createdAt: _now,
          updatedAt: _now,
        ),
      );
    await _pump(t, const CalendarPage(), [
      calendarEventRepositoryProvider.overrideWithValue(events),
    ]);
    expect(find.text('Rapat tim'), findsOneWidget);
    expect(find.text('09.00–10.30'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('cal-day-2026-10-06')));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Liburan'), findsOneWidget);
    expect(find.textContaining('Sepanjang hari'), findsOneWidget);
  });

  testWidgets('killa: 403 locks the feature and remembers it', (t) async {
    final killa = _Killa()
      ..error = const KillaException(
        KillaErrorKind.forbidden,
        'forbidden',
        status: 403,
      );
    late ProviderContainer container;
    await _pump(
      t,
      Consumer(
        builder: (context, ref, _) {
          container = ProviderScope.containerOf(context);
          return const KillaChatPage();
        },
      ),
      [killaRepositoryProvider.overrideWithValue(killa)],
    );
    expect(find.text('Killa masih terkunci'), findsOneWidget);
    expect(container.read(killaAccessProvider), KillaAccess.forbidden);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('killa: chat renders markdown replies and sends', (t) async {
    final killa = _Killa()
      ..messages.addAll([
        KillaMessage(
          id: 'w1',
          role: KillaRole.user,
          body: 'dari WA',
          channel: KillaChannel.wa,
          createdAt: _now.subtract(const Duration(days: 1)),
        ),
        KillaMessage(
          id: 's1',
          role: KillaRole.system,
          body: 'Sesi baru',
          createdAt: _now.subtract(const Duration(hours: 1)),
        ),
      ]);
    await _pump(t, const KillaChatPage(), [
      killaRepositoryProvider.overrideWithValue(killa),
      killaMediaPickerProvider.overrideWithValue(const _NoPicker()),
    ]);
    expect(find.text('WA'), findsOneWidget);
    expect(find.textContaining('Sesi baru'), findsOneWidget);
    expect(find.text('Kemarin'), findsOneWidget);

    await t.enterText(find.byKey(const ValueKey('killa-input')), 'halo');
    await t.pump();
    await t.tap(find.byKey(const ValueKey('killa-send')));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('halo'), findsOneWidget);
    expect(find.textContaining('Siap,'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('killa: persisted model is loaded and saved engine-side', (
    t,
  ) async {
    final killa = _Killa()..storedModel = 'opus';
    await _pump(t, const KillaChatPage(), [
      killaRepositoryProvider.overrideWithValue(killa),
      killaMediaPickerProvider.overrideWithValue(const _NoPicker()),
    ]);
    expect(find.text('Model: Opus'), findsOneWidget);

    await t.tap(find.byTooltip('Pilih model'));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('killa-model-default')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('killa-model-default')));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(killa.modelPosts, ['default']);
    expect(find.text('Model: Default'), findsOneWidget);
    expect(find.text('Model tersimpan (berlaku juga di WA)'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}

class _NoPicker implements KillaMediaPicker {
  const _NoPicker();
  @override
  Future<List<KillaOutgoingMedia>> pickPhotos({int max = 3}) async => const [];
  @override
  Future<KillaOutgoingMedia?> takePhoto() async => null;
  @override
  Future<List<KillaOutgoingMedia>> pickPdfs({int max = 3}) async => [
    KillaOutgoingMedia(
      name: 'a.pdf',
      mimeType: 'application/pdf',
      bytes: Uint8List(4),
    ),
  ];
}
