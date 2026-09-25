import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/design_system/design_system.dart';

import '_helpers.dart';

/// Holds the "preference" in a StatefulWidget, like BalancePrivacyScope.
class _Host extends StatefulWidget {
  const _Host({required this.child, this.hidden = false});
  final Widget child;
  final bool hidden;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late bool hidden = widget.hidden;
  void _toggle() => setState(() => hidden = !hidden);
  @override
  Widget build(BuildContext context) =>
      MoneyVisibility(hidden: hidden, onToggle: _toggle, child: widget.child);
}

void main() {
  testWidgets('MoneyText shows amounts when visible', (tester) async {
    await tester.pumpWidget(
      wrap(
        const _Host(
          child: Column(
            children: [
              MoneyText(amount: 25000, tone: MoneyTone.expense),
              MoneyText(amount: 1250000, tone: MoneyTone.neutral),
            ],
          ),
        ),
      ),
    );
    expect(find.text('-Rp 25.000'), findsOneWidget);
    expect(find.text('Rp 1.250.000'), findsOneWidget);
  });

  testWidgets('MoneyText masks when hidden (keeps expense/income sign)', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const _Host(
          hidden: true,
          child: Column(
            children: [
              MoneyText(amount: 25000, tone: MoneyTone.expense),
              MoneyText(amount: 5000, tone: MoneyTone.income),
              MoneyText(amount: -1250000, tone: MoneyTone.neutral),
              MoneyText(amount: 1250000, compact: true),
              MoneyText(text: 'Rp 1,2 jt'),
              MoneyText(amount: 12.5, currency: 'USD'),
            ],
          ),
        ),
      ),
    );
    expect(find.text('-Rp •••••'), findsOneWidget);
    expect(find.text('+Rp •••••'), findsOneWidget);
    expect(find.text('Rp •••••'), findsNWidgets(2)); // neutral + text
    expect(find.text('Rp •••'), findsOneWidget); // compact
    expect(find.text('\$ •••••'), findsOneWidget);
    expect(find.textContaining('1.250.000'), findsNothing);
    expect(find.textContaining('1,2'), findsNothing);
  });

  testWidgets('context.money, reveal() and the eye toggle', (tester) async {
    await tester.pumpWidget(
      wrap(
        _Host(
          hidden: true,
          child: Column(
            children: [
              const MoneyVisibilityToggle(key: ValueKey('eye')),
              Builder(builder: (c) => Text('Keluar ${c.money(40000)}')),
              MoneyVisibility.reveal(
                child: const MoneyText(
                  key: ValueKey('form'),
                  amount: 70000,
                  tone: MoneyTone.neutral,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Keluar Rp •••••'), findsOneWidget);
    expect(find.text('Rp 70.000'), findsOneWidget); // forms stay visible
    expect(find.byIcon(Icons.visibility_off_rounded), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('eye')));
    await tester.pumpAndSettle();
    expect(find.text('Keluar Rp 40.000'), findsOneWidget);
    expect(find.byIcon(Icons.visibility_rounded), findsOneWidget);
  });

  testWidgets('toggle renders nothing without a controller', (tester) async {
    await tester.pumpWidget(wrap(const MoneyVisibilityToggle()));
    expect(find.byType(IconButton), findsNothing);
  });

  testWidgets('MoneyPeek reveals only while long-pressed', (tester) async {
    await tester.pumpWidget(
      wrap(
        const _Host(
          hidden: true,
          child: MoneyPeek(
            child: SizedBox(
              width: 300,
              height: 80,
              child: MoneyText(amount: 900000, tone: MoneyTone.neutral),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Rp •••••'), findsOneWidget);
    final g = await tester.startGesture(
      tester.getCenter(find.byType(MoneyText)),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    expect(find.text('Rp 900.000'), findsOneWidget);
    await g.up();
    await tester.pump();
    expect(find.text('Rp •••••'), findsOneWidget);
  });
}
