// Mimpi manage screen: categories (add, rename, move-to delete) and custom
// columns (add, edit, delete with a warning). Invented data only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/presentation/features/dreams/dream_manage_logic.dart';
import 'package:ghina/presentation/features/dreams/dream_manage_page.dart';

import 'dreams_test_rig.dart';

DreamFieldDef _def(
  String key,
  String label, {
  DreamFieldType type = DreamFieldType.text,
  List<String>? appliesTo,
}) => DreamFieldDef(
  id: 'df-$key',
  key: key,
  label: label,
  type: type,
  appliesTo: appliesTo,
  createdAt: dreamsNow,
  updatedAt: dreamsNow,
);

Future<void> _type(WidgetTester t, String key, String text) async {
  await t.enterText(
    find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.byType(TextField),
    ),
    text,
  );
  await t.pump();
}

// Dialogs carry the looping mascot, so pumpAndSettle never settles.
Future<void> _sheet(WidgetTester t) => settle(t);

void main() {
  group('logic', () {
    test('parseFieldOptions splits on commas and new lines', () {
      expect(parseFieldOptions('Kecil, Sedang\nBesar,, \n'), [
        'Kecil',
        'Sedang',
        'Besar',
      ]);
      expect(parseFieldOptions('  '), isEmpty);
    });

    test('moveTargets leaves the deleted one and always offers other', () {
      final cats = [
        categoryFixture('travel', 'Perjalanan', '🧳'),
        categoryFixture('money', 'Uang', '💰'),
      ];
      expect(moveTargets(cats, 'travel').map((t) => t.key), ['money', 'other']);
      final withOther = [...cats, categoryFixture('other', 'Lainnya', '✨')];
      expect(moveTargets(withOther, 'travel').map((t) => t.key), [
        'money',
        'other',
      ]);
    });

    test('counts and scope text', () {
      final dreams = [
        dreamFixture('a', category: 'travel').copyWith(fields: {'x': 1}),
        dreamFixture('b', category: 'travel'),
        dreamFixture('c', category: 'money').copyWith(fields: {'x': 'y'}),
      ];
      expect(dreamsInCategory(dreams, 'travel').length, 2);
      expect(dreamsWithFieldCount(dreams, 'x'), 2);
      expect(dreamsWithFieldCount(dreams, 'z'), 0);
      final cats = [categoryFixture('travel', 'Perjalanan', '🧳')];
      expect(fieldScopeText(_def('x', 'X'), cats), 'semua kategori');
      expect(
        fieldScopeText(_def('x', 'X', appliesTo: ['travel', 'zzz']), cats),
        'Perjalanan, zzz',
      );
    });
  });

  group('page', () {
    DreamsRig rig() => DreamsRig(
      categories: [
        categoryFixture('travel', 'Perjalanan', '🧳'),
        categoryFixture('money', 'Uang', '💰'),
        categoryFixture('other', 'Lainnya', '✨'),
      ],
      dreams: [
        dreamFixture(
          'd1',
          title: 'Trip contoh ke Kota Sample',
          category: 'travel',
        ).copyWith(fields: {'anggaran': 'Rp 5 juta'}),
        dreamFixture(
          'd2',
          title: 'Mimpi contoh',
          category: 'travel',
        ).copyWith(fields: {'anggaran': 'Rp 1 juta'}),
        dreamFixture('d3', title: 'Buku contoh', category: 'money'),
      ],
      fields: [_def('anggaran', 'Anggaran')],
    );

    Future<void> pump(WidgetTester t, DreamsRig r) =>
        r.pump(t, '/dreams', () => const DreamManagePage());

    testWidgets('lists categories with their keys and columns with scope', (
      t,
    ) async {
      final r = rig();
      await pump(t, r);
      expect(find.text('Perjalanan'), findsOneWidget);
      expect(find.text('travel'), findsOneWidget);
      expect(find.text('Anggaran'), findsOneWidget);
      expect(find.text('Teks · semua kategori'), findsOneWidget);
      // The built-in "other" cannot be deleted.
      expect(find.byKey(const ValueKey('cat-delete-dc-other')), findsNothing);
      expect(
        find.byKey(const ValueKey('cat-delete-dc-travel')),
        findsOneWidget,
      );
    });

    testWidgets('add a category', (t) async {
      final r = rig();
      await pump(t, r);
      await tapKey(t, 'add-category');
      await _sheet(t);
      await _type(t, 'category-emoji', '🏠');
      await _type(t, 'category-label', 'Rumah contoh');
      await tapKey(t, 'category-save');
      final added = r.cats.s.items.values.where(
        (c) => c.label == 'Rumah contoh',
      );
      expect(added.length, 1);
      expect(added.single.emoji, '🏠');
      expect(added.single.key, 'rumah_contoh');
      expect(find.text('Rumah contoh'), findsOneWidget);
    });

    testWidgets('rename keeps the key', (t) async {
      final r = rig();
      await pump(t, r);
      await tapKey(t, 'cat-dc-money');
      await _sheet(t);
      expect(
        find.textContaining('Kunci "money" tidak berubah'),
        findsOneWidget,
      );
      await _type(t, 'category-label', 'Keuangan contoh');
      await tapKey(t, 'category-save');
      final c = r.cats.s.items['dc-money']!;
      expect([c.label, c.key], ['Keuangan contoh', 'money']);
    });

    testWidgets('delete asks where the dreams go, moves them, then deletes', (
      t,
    ) async {
      final r = rig();
      await pump(t, r);
      await tapKey(t, 'cat-delete-dc-travel');
      await _sheet(t);
      expect(find.textContaining('2 mimpi di'), findsOneWidget);
      // The deleted category is not offered as a target.
      expect(find.byKey(const ValueKey('move-to-travel')), findsNothing);
      await tapKey(t, 'move-to-money');
      await tapKey(t, 'move-confirm');
      expect(r.cats.s.items.containsKey('dc-travel'), isFalse);
      expect(r.repo.s.items['d1']!.category, 'money');
      expect(r.repo.s.items['d2']!.category, 'money');
      expect(r.repo.s.items['d3']!.category, 'money');
      expect(find.text('travel'), findsNothing);
    });

    testWidgets('cancel leaves everything as it was', (t) async {
      final r = rig();
      await pump(t, r);
      await tapKey(t, 'cat-delete-dc-travel');
      await _sheet(t);
      await tapKey(t, 'move-cancel');
      expect(r.cats.s.items.containsKey('dc-travel'), isTrue);
      expect(r.repo.s.items['d1']!.category, 'travel');
    });

    testWidgets('an empty category is deleted after a plain confirm', (
      t,
    ) async {
      final r = rig();
      await pump(t, r);
      await tapKey(t, 'cat-delete-dc-money');
      await _sheet(t);
      // money holds d3, so move it first.
      await tapKey(t, 'move-confirm');
      expect(r.repo.s.items['d3']!.category, 'other');
      await tapKey(t, 'add-category');
      await _sheet(t);
      await _type(t, 'category-label', 'Kosong contoh');
      await tapKey(t, 'category-save');
      final id = r.cats.s.items.values
          .firstWhere((c) => c.label == 'Kosong contoh')
          .id;
      await tapKey(t, 'cat-delete-$id');
      await _sheet(t);
      await tapText(t, 'HAPUS KATEGORI');
      expect(r.cats.s.items.containsKey(id), isFalse);
    });

    testWidgets('add a text column and a choice column for one category', (
      t,
    ) async {
      final r = rig();
      await pump(t, r);
      await tapKey(t, 'add-field');
      await _sheet(t);
      await _type(t, 'field-label', 'Lokasi contoh');
      await tapKey(t, 'field-save');
      var d = r.defs.s.items.values.firstWhere(
        (x) => x.label == 'Lokasi contoh',
      );
      expect(
        [d.key, d.type, d.appliesTo],
        ['lokasi_contoh', DreamFieldType.text, null],
      );
      expect(find.text('Teks · semua kategori'), findsNWidgets(2));

      await tapKey(t, 'add-field');
      await _sheet(t);
      await _type(t, 'field-label', 'Ukuran contoh');
      await tapText(t, 'Pilihan');
      await _sheet(t);
      await _type(t, 'field-options', 'Kecil, Besar\nSedang');
      await tapText(t, '🧳 Perjalanan');
      await tapKey(t, 'field-save');
      d = r.defs.s.items.values.firstWhere((x) => x.label == 'Ukuran contoh');
      expect(d.type, DreamFieldType.select);
      expect(d.options, ['Kecil', 'Besar', 'Sedang']);
      expect(d.appliesTo, ['travel']);
      expect(find.text('Pilihan · Perjalanan'), findsOneWidget);
    });

    testWidgets('a select column without options shows the domain message', (
      t,
    ) async {
      final r = rig();
      await pump(t, r);
      await tapKey(t, 'add-field');
      await _sheet(t);
      await _type(t, 'field-label', 'Kosong contoh');
      await tapText(t, 'Pilihan');
      await _sheet(t);
      await tapKey(t, 'field-save');
      expect(r.defs.s.items.length, 1);
      expect(find.text('Pilihan wajib diisi'), findsOneWidget);
    });

    testWidgets('edit a column: label, scope and list flag; type stays', (
      t,
    ) async {
      final r = rig();
      await pump(t, r);
      await tapKey(t, 'def-df-anggaran');
      await _sheet(t);
      expect(find.textContaining('Jenis: Teks'), findsOneWidget);
      expect(find.byKey(const ValueKey('field-type')), findsNothing);
      await _type(t, 'field-label', 'Anggaran contoh');
      await tapText(t, '💰 Uang');
      await tapText(t, 'Tampilkan di daftar');
      await tapKey(t, 'field-save');
      final d = r.defs.s.items['df-anggaran']!;
      expect(d.label, 'Anggaran contoh');
      expect(d.key, 'anggaran');
      expect(d.type, DreamFieldType.text);
      expect(d.appliesTo, ['money']);
      expect(d.showInList, isTrue);
    });

    testWidgets('delete warns with the number of dreams holding the key', (
      t,
    ) async {
      final r = rig();
      await pump(t, r);
      await tapKey(t, 'def-delete-df-anggaran');
      await _sheet(t);
      expect(find.textContaining('2 mimpi punya isi'), findsOneWidget);
      await tapText(t, 'HAPUS KOLOM');
      expect(r.defs.s.items, isEmpty);
      expect(find.text('Anggaran'), findsNothing);
    });

    testWidgets('cancelling the warning keeps the column', (t) async {
      final r = rig();
      await pump(t, r);
      await tapKey(t, 'def-delete-df-anggaran');
      await _sheet(t);
      await tapText(t, 'BATAL');
      expect(r.defs.s.items.length, 1);
    });
  });
}
