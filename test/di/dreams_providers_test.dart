// The Dreams providers wired to the in-memory fakes: reads stream, writes go
// through the use cases with their rules, the online reads are reachable.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/failure.dart';
import 'package:ghina/di/dreams_providers.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';

import '../domain/dreams_fakes.dart';
import 'dreams_test_overrides.dart';

void main() {
  late ProviderContainer c;
  late FakeDreamOnlineRepository online;

  setUp(() {
    online = FakeDreamOnlineRepository();
    c = ProviderContainer(overrides: dreamsFakeOverrides(online: online));
  });
  tearDown(() => c.dispose());

  test('a dream created through the provider shows up in the list', () async {
    final r = await c.read(createDreamProvider)(
      const DreamInput(title: 'Mimpi contoh', category: 'other'),
    );
    expect(r.isOk, isTrue);
    final sub = c.listen(watchDreamsProvider, (_, _) {});
    final list = await c.read(watchDreamsProvider.future);
    sub.close();
    expect(list.map((d) => d.title), ['Mimpi contoh']);
  });

  test(
    'the local detail follows the steps added through the providers',
    () async {
      final d = (await c.read(createDreamProvider)(
        const DreamInput(title: 'Trip contoh ke Kota Sample'),
      )).valueOrThrow;
      await c.read(saveDreamStepProvider)(
        dreamId: d.id,
        input: const DreamStepInput(title: 'Pesan tiket contoh'),
      );
      final sub = c.listen(watchDreamLocalDetailProvider(d.id), (_, _) {});
      final detail = await c.read(watchDreamLocalDetailProvider(d.id).future);
      sub.close();
      expect(detail!.steps.map((s) => s.title), ['Pesan tiket contoh']);
    },
  );

  test('the summary is read from the online repository', () async {
    online.summaryValue = const DreamSummary(date: '2026-10-10', total: 1);
    final r = await c.read(getDreamSummaryProvider)();
    expect(r.valueOrThrow.total, 1);
  });

  test(
    'offline, the online reads say so instead of inventing numbers',
    () async {
      online.failure = const NetworkFailure();
      final r = await c.read(getDreamDetailProvider)('id-1');
      expect(r.failureOrNull, isA<NetworkFailure>());
    },
  );
}
