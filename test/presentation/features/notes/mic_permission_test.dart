import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/data/platform/fakes.dart';
import 'package:ghina/domain/services/services.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/notes/widgets/mic_permission.dart';
import 'package:ghina/presentation/state/platform/platform_state.dart';

/// ensureMicReady (notes / Killa): one prompt per tap, true only when the
/// mic is usable — the caller then starts at once.
void main() {
  late FakeMicrophonePermission mic;
  final results = <bool>[];

  Future<void> pump(WidgetTester t) async {
    results.clear();
    await t.pumpWidget(
      ProviderScope(
        overrides: [microphonePermissionProvider.overrideWithValue(mic)],
        child: MaterialApp(
          theme: GhinaTheme.light(),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () async => results.add(
                  await ensureMicReady(context, ref, MicPurpose.dictate),
                ),
                child: const Text('mic'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> tap(WidgetTester t, Finder f) async {
    await t.tap(f);
    await settle(t);
  }

  Finder key(String k) => find.byKey(ValueKey(k));

  testWidgets('sudah diizinkan → langsung true, tanpa dialog', (t) async {
    mic = FakeMicrophonePermission();
    await pump(t);
    await tap(t, find.text('mic'));
    expect(results, [true]);
    expect(mic.requests, 0);
  });

  testWidgets('jelaskan → izin sistem → true', (t) async {
    mic = FakeMicrophonePermission(MicPermissionStatus.denied)
      ..afterRequest = MicPermissionStatus.granted;
    await pump(t);
    await tap(t, find.text('mic'));
    expect(find.text('Izinkan mikrofon untuk dikte'), findsOneWidget);
    await tap(t, key('mic-allow'));
    expect(results, [true]);
    expect(mic.requests, 1);
  });

  testWidgets('ditolak → Coba lagi → true (satu prompt per ketuk)', (t) async {
    mic = FakeMicrophonePermission(MicPermissionStatus.denied)
      ..afterRequest = MicPermissionStatus.denied;
    await pump(t);
    await tap(t, find.text('mic'));
    await tap(t, key('mic-allow'));
    expect(mic.requests, 1);
    expect(find.text('Mikrofon belum diizinkan'), findsOneWidget);
    mic.afterRequest = MicPermissionStatus.granted;
    await tap(t, key('mic-retry'));
    expect(mic.requests, 2);
    expect(results, [true]);
  });

  testWidgets('diblokir → sheet pengaturan → kembali diizinkan → true', (
    t,
  ) async {
    mic = FakeMicrophonePermission(MicPermissionStatus.permanentlyDenied);
    await pump(t);
    await tap(t, find.text('mic'));
    expect(find.text('Mikrofon masih diblokir'), findsOneWidget);
    await tap(t, key('mic-settings'));
    expect(mic.settingsOpened, 1);
    expect(results, isEmpty); // menunggu kembali dari Pengaturan
    mic.current = MicPermissionStatus.granted;
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(t);
    expect(results, [true]);
    expect(mic.requests, 0);
  });

  testWidgets('diblokir → kembali tetap diblokir → false + pesan', (t) async {
    mic = FakeMicrophonePermission(MicPermissionStatus.permanentlyDenied);
    await pump(t);
    await tap(t, find.text('mic'));
    await tap(t, key('mic-settings'));
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(t);
    expect(results, [false]);
    expect(find.text('Mikrofon masih belum diizinkan'), findsOneWidget);
    await t.pump(const Duration(seconds: 5));
  });
}
