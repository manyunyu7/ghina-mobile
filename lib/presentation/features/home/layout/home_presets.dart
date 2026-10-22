import 'package:flutter/material.dart';

import 'home_layout.dart';

/// A ready-made Beranda: which cards, in which order and size.
@immutable
class HomePreset {
  const HomePreset({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.entries,
  });

  final String id;
  final String name;
  final String description;
  final IconData icon;
  final List<HomeEntry> entries;

  HomeLayout toLayout() => HomeLayout(entries, presetId: id);
}

const _s = HomeCardSize.small;
const _w = HomeCardSize.wide;

/// The default: every card the app showed before Beranda became editable.
const homeDefaultPresetId = 'seimbang';

const homePresets = <HomePreset>[
  HomePreset(
    id: homeDefaultPresetId,
    name: 'Seimbang',
    description: 'Uang, tugas, kebiasaan, dan Kantor dalam satu layar.',
    icon: Icons.balance_rounded,
    entries: [
      HomeEntry(HomeCard.mascot),
      HomeEntry(HomeCard.balance),
      HomeEntry(HomeCard.monthFlow),
      HomeEntry(HomeCard.tasks),
      HomeEntry(HomeCard.habits),
      HomeEntry(HomeCard.todayPosts),
      HomeEntry(HomeCard.kantor),
      HomeEntry(HomeCard.learning),
      HomeEntry(HomeCard.menu),
      HomeEntry(HomeCard.spending),
      HomeEntry(HomeCard.budgets),
      HomeEntry(HomeCard.bills),
      HomeEntry(HomeCard.recent),
    ],
  ),
  HomePreset(
    id: 'keuangan',
    name: 'Keuangan',
    description: 'Saldo, arus, anggaran, dan tagihan di depan.',
    icon: Icons.payments_rounded,
    entries: [
      HomeEntry(HomeCard.balance),
      HomeEntry(HomeCard.monthFlow),
      HomeEntry(HomeCard.budgets),
      HomeEntry(HomeCard.spending),
      HomeEntry(HomeCard.bills),
      HomeEntry(HomeCard.wallets, _w),
      HomeEntry(HomeCard.recent),
      HomeEntry(HomeCard.menu),
    ],
  ),
  HomePreset(
    id: 'produktif',
    name: 'Produktif',
    description: 'Tugas, pengingat, kalender, dan kebiasaan.',
    icon: Icons.bolt_rounded,
    entries: [
      HomeEntry(HomeCard.tasks),
      HomeEntry(HomeCard.agenda, _s),
      HomeEntry(HomeCard.calendar, _s),
      HomeEntry(HomeCard.habits),
      HomeEntry(HomeCard.todayPosts),
      HomeEntry(HomeCard.notes, _s),
      HomeEntry(HomeCard.kantor, _s),
      HomeEntry(HomeCard.learning),
      HomeEntry(HomeCard.mascot),
    ],
  ),
  HomePreset(
    id: 'ibadah',
    name: 'Ibadah',
    description: 'Sholat dan kebiasaan baik lebih dulu, uang ringkas.',
    icon: Icons.mosque_rounded,
    entries: [
      HomeEntry(HomeCard.prayers),
      HomeEntry(HomeCard.habits),
      HomeEntry(HomeCard.agenda, _s),
      HomeEntry(HomeCard.dreams, _s),
      HomeEntry(HomeCard.mascot),
      HomeEntry(HomeCard.balance),
      HomeEntry(HomeCard.menu),
    ],
  ),
  HomePreset(
    id: 'sehat',
    name: 'Sehat',
    description: 'Kebiasaan, sholat, dan target harian untuk rutinitas.',
    icon: Icons.favorite_rounded,
    entries: [
      HomeEntry(HomeCard.mascot),
      HomeEntry(HomeCard.habits),
      HomeEntry(HomeCard.prayers, _s),
      HomeEntry(HomeCard.agenda, _s),
      HomeEntry(HomeCard.tasks),
      HomeEntry(HomeCard.learning),
      HomeEntry(HomeCard.wallets, _s),
      HomeEntry(HomeCard.notes, _s),
    ],
  ),
  HomePreset(
    id: 'investor',
    name: 'Investor',
    description: 'Portofolio, screener, dan saldo.',
    icon: Icons.trending_up_rounded,
    entries: [
      HomeEntry(HomeCard.balance),
      HomeEntry(HomeCard.portfolio, _w),
      HomeEntry(HomeCard.screener, _s),
      HomeEntry(HomeCard.wallets, _s),
      HomeEntry(HomeCard.monthFlow),
      HomeEntry(HomeCard.killa),
      HomeEntry(HomeCard.bills),
      HomeEntry(HomeCard.recent),
    ],
  ),
  HomePreset(
    id: 'developer',
    name: 'Developer / Kantor',
    description: 'Kantor Claude dan Killa paling atas, lalu tugas.',
    icon: Icons.terminal_rounded,
    entries: [
      HomeEntry(HomeCard.kantor),
      HomeEntry(HomeCard.killa, _s),
      HomeEntry(HomeCard.agenda, _s),
      HomeEntry(HomeCard.tasks),
      HomeEntry(HomeCard.calendar, _s),
      HomeEntry(HomeCard.notes, _s),
      HomeEntry(HomeCard.habits),
      HomeEntry(HomeCard.balance),
    ],
  ),
  HomePreset(
    id: 'minimalis',
    name: 'Minimalis',
    description: 'Hanya yang paling penting: saldo, tugas, dan menu.',
    icon: Icons.crop_square_rounded,
    entries: [
      HomeEntry(HomeCard.balance),
      HomeEntry(HomeCard.tasks),
      HomeEntry(HomeCard.menu),
    ],
  ),
  HomePreset(
    id: 'pagi',
    name: 'Pagi',
    description: 'Mulai hari: sholat, agenda, kebiasaan, dan tugas.',
    icon: Icons.wb_sunny_rounded,
    entries: [
      HomeEntry(HomeCard.mascot),
      HomeEntry(HomeCard.prayers, _s),
      HomeEntry(HomeCard.calendar, _s),
      HomeEntry(HomeCard.agenda, _w),
      HomeEntry(HomeCard.habits),
      HomeEntry(HomeCard.tasks),
      HomeEntry(HomeCard.people, _s),
      HomeEntry(HomeCard.wallets, _s),
    ],
  ),
  HomePreset(
    id: 'malam',
    name: 'Malam',
    description: 'Tutup hari: transaksi, kebiasaan, mimpi, dan catatan.',
    icon: Icons.nightlight_round,
    entries: [
      HomeEntry(HomeCard.monthFlow),
      HomeEntry(HomeCard.recent),
      HomeEntry(HomeCard.habits),
      HomeEntry(HomeCard.dreams, _s),
      HomeEntry(HomeCard.notes, _s),
      HomeEntry(HomeCard.prayers),
      HomeEntry(HomeCard.mascot),
    ],
  ),
];

HomePreset? homePresetById(String? id) {
  for (final p in homePresets) {
    if (p.id == id) return p;
  }
  return null;
}

/// The layout a fresh install gets.
HomeLayout homeDefaultLayout() => homePresets.first.toLayout();
