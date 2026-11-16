// Kanban column layout per board width, offline (fake board, no daemon).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/kantor/board/kantor_board_data.dart';
import 'package:ghina/presentation/features/kantor/board/kantor_board_lib.dart';
import 'package:ghina/presentation/features/kantor/board/kantor_board_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _office = 'o1';

class _FakeBoard extends KBoardNotifier {
  _FakeBoard() : super(_office);

  @override
  Future<KBoard> build() async => KBoard([
    for (var i = 0; i < 5; i++)
      KCard.fromJson({'id': 'c$i', 'title': 'Kartu $i', 'col': i, 'ord': 1}),
  ], const []);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpBoard(
    WidgetTester t, {
    required double screen,
    double? panel,
  }) async {
    t.view.physicalSize = Size(screen, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    const board = KantorBoardTab(officeId: _office);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          kantorBoardProvider(_office).overrideWith(_FakeBoard.new),
          kantorOfficeProvider(_office).overrideWith(
            (_) async => KOffice(roles: [], rooms: [], workingRoles: {}),
          ),
        ],
        child: MaterialApp(
          theme: GhinaTheme.light(),
          home: Scaffold(
            body: panel == null
                ? board
                : Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(width: panel, child: board),
                  ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  /// The card list of each built column, left to right.
  List<Rect> columns(WidgetTester t) {
    final f = find.descendant(
      of: find.byType(PageView),
      matching: find.byWidgetPredicate(
        (w) => w is ListView && w.scrollDirection == Axis.vertical,
      ),
    );
    return [
      for (final e in f.evaluate())
        if (e.renderObject case final RenderBox box)
          box.localToGlobal(Offset.zero) & box.size,
    ]..sort((a, b) => a.left.compareTo(b.left));
  }

  /// Columns fully inside [left, right].
  List<Rect> fullyVisible(WidgetTester t, double left, double right) => [
    for (final r in columns(t))
      if (r.left >= left - 0.5 && r.right <= right + 0.5) r,
  ];

  test('column width per board width', () {
    expect(kBoardColumnWidth(600), 300);
    expect(kBoardColumnWidth(690), 345); // Fold open, upright: 2
    expect(kBoardColumnWidth(900), 300); // 3
    expect(kBoardColumnWidth(1000), closeTo(333.3, 0.1)); // 3
    expect(kBoardColumnWidth(1200), 300); // 4
    expect(kBoardColumnWidth(830), 320); // 2 + peek
    for (var w = 600.0; w <= 1600; w += 10) {
      expect(kBoardColumnWidth(w), inInclusiveRange(300, 350));
    }
  });

  testWidgets('400dp: one column per screen, unchanged 0.88 paging', (t) async {
    await pumpBoard(t, screen: 400);
    expect(t.takeException(), isNull);
    expect(find.text('Backlog'), findsOneWidget);
    final cols = columns(t);
    // page = 0.88 * 400 = 352; column padding 6 + 6.
    expect(cols.first.left, closeTo(6, 0.5));
    expect(cols.first.width, closeTo(352 - 12, 0.5));
    expect(cols[1].left, closeTo(352 + 6, 0.5));
    expect(fullyVisible(t, 0, 400), hasLength(1));

    // one swipe = one column
    await t.fling(find.byType(PageView), const Offset(-200, 0), 800);
    await t.pumpAndSettle();
    final moved = fullyVisible(t, 0, 400);
    expect(moved, hasLength(1));
    expect(find.text('Siap'), findsOneWidget);
    expect(t.getTopLeft(find.text('Siap')).dx, lessThan(60));
  });

  testWidgets('900dp: several fixed-width columns side by side', (t) async {
    await pumpBoard(t, screen: 900);
    expect(t.takeException(), isNull);
    final vis = fullyVisible(t, 0, 900);
    expect(vis.length, greaterThanOrEqualTo(2));
    for (final r in vis) {
      expect(r.width + 12, inInclusiveRange(300, 350));
      expect(r.top, vis.first.top);
    }
    for (final name in ['Backlog', 'Siap', 'Dikerjakan']) {
      expect(find.text(name), findsOneWidget);
    }
    // more columns than fit: still scrolls sideways to the last one
    await t.drag(find.byType(PageView), const Offset(-700, 0));
    await t.pumpAndSettle();
    final last = columns(t).last;
    expect(find.text('Selesai'), findsOneWidget);
    expect(last.right, lessThanOrEqualTo(900.5));
    expect(last.right, greaterThan(850));
  });

  testWidgets('narrow panel on a wide screen pages like a phone', (t) async {
    await pumpBoard(t, screen: 1000, panel: 400);
    expect(t.takeException(), isNull);
    expect(columns(t).first.width, closeTo(352 - 12, 0.5));
    expect(fullyVisible(t, 0, 400), hasLength(1));
  });
}
