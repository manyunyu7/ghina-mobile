// Where a share goes: a PDF opens the statement import, anything else the
// Notes flow.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/services/share_intake.dart';
import 'package:ghina/presentation/features/shell/share_intake_listener.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('a payload with a PDF is routed to /transactions/import', (
    tester,
  ) async {
    Object? extra;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => dispatchSharedPayload(
                context,
                ref,
                SharedPayload.normalize(
                  subject: 'mutasi.pdf',
                  pdfPaths: ['/cache/share_intake/1/mutasi.pdf'],
                ),
              ),
              child: const Text('share'),
            ),
          ),
        ),
        GoRoute(
          path: '/transactions/import',
          builder: (_, s) {
            extra = s.extra;
            return const Text('IMPOR');
          },
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.tap(find.text('share'));
    await tester.pumpAndSettle();
    expect(find.text('IMPOR'), findsOneWidget);
    expect(extra, '/cache/share_intake/1/mutasi.pdf');
  });
}
