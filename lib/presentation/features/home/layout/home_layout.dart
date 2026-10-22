import 'dart:convert';

import 'package:flutter/material.dart';

/// How much room a Beranda card takes. [small] is a half-width tile (two in a
/// row), [medium] is the normal full-width card and [wide] is full width with
/// extra detail rows where the card has them.
enum HomeCardSize {
  small('Kecil'),
  medium('Sedang'),
  wide('Lebar');

  const HomeCardSize(this.label);
  final String label;
}

/// Every card Beranda can show. The wire id is what gets stored, so never
/// rename one.
enum HomeCard {
  mascot('mascot', 'Maskot & target harian', Icons.emoji_emotions_rounded, {
    HomeCardSize.medium,
  }),
  balance('balance', 'Total saldo', Icons.account_balance_wallet_rounded, {
    HomeCardSize.medium,
  }),
  wallets('wallets', 'Dompet', Icons.wallet_rounded, {
    HomeCardSize.small,
    HomeCardSize.medium,
    HomeCardSize.wide,
  }),
  monthFlow('month-flow', 'Arus bulan ini', Icons.swap_vert_rounded, {
    HomeCardSize.medium,
  }),
  tasks('tasks', 'Tugas FIRE', Icons.task_alt_rounded, {HomeCardSize.medium}),
  habits('habits', 'Kebiasaan hari ini', Icons.local_fire_department_rounded, {
    HomeCardSize.small,
    HomeCardSize.medium,
  }),
  agenda('agenda', 'Pengingat', Icons.notifications_active_rounded, {
    HomeCardSize.small,
    HomeCardSize.medium,
    HomeCardSize.wide,
  }),
  calendar('calendar', 'Kalender', Icons.event_rounded, {
    HomeCardSize.small,
    HomeCardSize.medium,
    HomeCardSize.wide,
  }),
  todayPosts('today-posts', 'Konten hari ini', Icons.rocket_launch_rounded, {
    HomeCardSize.medium,
  }),
  kantor('kantor', 'Kantor Claude', Icons.apartment_rounded, {
    HomeCardSize.small,
    HomeCardSize.medium,
  }),
  killa('killa', 'Killa', Icons.chat_bubble_rounded, {
    HomeCardSize.small,
    HomeCardSize.medium,
  }),
  portfolio('portfolio', 'Portofolio', Icons.show_chart_rounded, {
    HomeCardSize.small,
    HomeCardSize.medium,
    HomeCardSize.wide,
  }),
  screener('screener', 'Screener saham', Icons.manage_search_rounded, {
    HomeCardSize.small,
    HomeCardSize.medium,
  }),
  learning('learning', 'Lanjut belajar', Icons.school_rounded, {
    HomeCardSize.medium,
  }),
  prayers('prayers', 'Sholat', Icons.mosque_rounded, {
    HomeCardSize.small,
    HomeCardSize.medium,
  }),
  dreams('dreams', 'Mimpi', Icons.auto_awesome_rounded, {
    HomeCardSize.small,
    HomeCardSize.medium,
    HomeCardSize.wide,
  }),
  people('people', 'Orang & tanggal penting', Icons.cake_rounded, {
    HomeCardSize.small,
    HomeCardSize.medium,
    HomeCardSize.wide,
  }),
  notes('notes', 'Catatan', Icons.sticky_note_2_rounded, {
    HomeCardSize.small,
    HomeCardSize.medium,
  }),
  menu('menu', 'Menu pintas', Icons.apps_rounded, {HomeCardSize.medium}),
  spending('spending', 'Pengeluaran bulan ini', Icons.donut_small_rounded, {
    HomeCardSize.medium,
  }),
  budgets('budgets', 'Anggaran', Icons.savings_rounded, {HomeCardSize.medium}),
  bills('bills', 'Tagihan sebentar lagi', Icons.receipt_long_rounded, {
    HomeCardSize.medium,
  }),
  recent('recent', 'Transaksi terakhir', Icons.history_rounded, {
    HomeCardSize.medium,
  });

  const HomeCard(this.wire, this.title, this.icon, this.sizes);

  final String wire;
  final String title;
  final IconData icon;

  /// The sizes this card can take; the first-listed medium is the default.
  final Set<HomeCardSize> sizes;

  HomeCardSize get defaultSize =>
      sizes.contains(HomeCardSize.medium) ? HomeCardSize.medium : sizes.first;

  static HomeCard? byWire(Object? wire) {
    for (final c in values) {
      if (c.wire == wire) return c;
    }
    return null;
  }
}

/// One card placed on Beranda.
@immutable
class HomeEntry {
  const HomeEntry(this.card, [HomeCardSize? size]) : _size = size;

  final HomeCard card;
  final HomeCardSize? _size;

  /// Never a size the card does not support.
  HomeCardSize get size =>
      _size != null && card.sizes.contains(_size) ? _size : card.defaultSize;

  HomeEntry withSize(HomeCardSize s) => HomeEntry(card, s);

  @override
  bool operator ==(Object other) =>
      other is HomeEntry && other.card == card && other.size == size;

  @override
  int get hashCode => Object.hash(card, size);
}

/// The ordered cards on Beranda. A card not listed is hidden.
@immutable
class HomeLayout {
  const HomeLayout(this.entries, {this.presetId});

  final List<HomeEntry> entries;

  /// The preset this started from (kept even after edits, for the editor).
  final String? presetId;

  bool has(HomeCard c) => entries.any((e) => e.card == c);

  /// Cards not on Beranda, in catalog order.
  List<HomeCard> get hidden => [
    for (final c in HomeCard.values)
      if (!has(c)) c,
  ];

  HomeLayout add(HomeCard c, [HomeCardSize? size]) => has(c)
      ? this
      : HomeLayout([...entries, HomeEntry(c, size)], presetId: presetId);

  HomeLayout remove(HomeCard c) => HomeLayout([
    for (final e in entries)
      if (e.card != c) e,
  ], presetId: presetId);

  HomeLayout resize(HomeCard c, HomeCardSize s) => HomeLayout([
    for (final e in entries) e.card == c ? e.withSize(s) : e,
  ], presetId: presetId);

  /// Moves the entry at [from] so it ends up at index [to] of the result.
  HomeLayout move(int from, int to) {
    if (from < 0 || from >= entries.length) return this;
    final list = [...entries];
    final e = list.removeAt(from);
    list.insert(to.clamp(0, list.length), e);
    return HomeLayout(list, presetId: presetId);
  }

  String encode() => jsonEncode({
    'v': 1,
    'preset': presetId,
    'cards': [
      for (final e in entries) {'id': e.card.wire, 'size': e.size.name},
    ],
  });

  /// Null when [raw] is missing or unreadable. Unknown ids (from a newer
  /// app) are dropped and duplicates ignored.
  static HomeLayout? decode(String? raw) {
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw);
      if (m is! Map || m['cards'] is! List) return null;
      final seen = <HomeCard>{};
      final out = <HomeEntry>[];
      for (final c in m['cards'] as List) {
        if (c is! Map) continue;
        final card = HomeCard.byWire(c['id']);
        if (card == null || !seen.add(card)) continue;
        final size = HomeCardSize.values
            .where((s) => s.name == c['size'])
            .firstOrNull;
        out.add(HomeEntry(card, size));
      }
      return HomeLayout(out, presetId: m['preset'] as String?);
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is HomeLayout &&
      other.presetId == presetId &&
      _listEq(other.entries, entries);

  @override
  int get hashCode => Object.hash(presetId, Object.hashAll(entries));

  static bool _listEq(List<HomeEntry> a, List<HomeEntry> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
