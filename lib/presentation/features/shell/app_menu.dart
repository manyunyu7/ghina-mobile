import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../design_system/design_system.dart';

/// Groups of the side drawer ("Semua menu").
enum AppMenuGroup {
  money('UANG'),
  life('HIDUP'),
  productive('PRODUKTIF'),
  other('LAINNYA');

  const AppMenuGroup(this.label);
  final String label;
}

/// One destination of the side drawer / the Beranda shortcut grid. The single
/// source of truth for menu labels, icons and colors.
@immutable
class AppMenuItem {
  const AppMenuItem({
    required this.label,
    required this.icon,
    required this.color,
    required this.path,
    required this.group,
    this.synonyms = const [],
    this.isTab = false,
    this.longPressPath,
    this.androidOnly = false,
  });

  final String label;
  final IconData icon;
  final ChunkySwatch color;
  final String path;
  final AppMenuGroup group;

  /// Extra search words (lower case), e.g. "saham" → Investasi.
  final List<String> synonyms;

  /// A bottom-nav tab: navigate with `go` (switch branch), not `push`.
  final bool isTab;

  /// Shortcut on long-press in the Beranda grid (Catatan → new note).
  final String? longPressPath;

  /// Hidden on other platforms (Log Notifikasi: iOS can't read other apps'
  /// notifications).
  final bool androidOnly;
}

const kAppMenu = <AppMenuItem>[
  // ---- UANG
  AppMenuItem(
    label: 'Dompet',
    icon: Icons.account_balance_wallet_rounded,
    color: GhinaColors.blue,
    path: '/wallets',
    group: AppMenuGroup.money,
    synonyms: ['wallet', 'rekening', 'bank', 'saldo', 'transfer', 'ewallet'],
  ),
  AppMenuItem(
    label: 'Transaksi',
    icon: Icons.receipt_long_rounded,
    color: GhinaColors.orange,
    path: '/transactions',
    group: AppMenuGroup.money,
    isTab: true,
    synonyms: [
      'pengeluaran',
      'pemasukan',
      'catat',
      'riwayat',
      'belanja',
      'expense',
      'income',
    ],
  ),
  AppMenuItem(
    label: 'Budget',
    icon: Icons.pie_chart_rounded,
    color: GhinaColors.green,
    path: '/budgets',
    group: AppMenuGroup.money,
    synonyms: ['anggaran', 'batas', 'limit', 'hati'],
  ),
  AppMenuItem(
    label: 'Langganan',
    icon: Icons.autorenew_rounded,
    color: GhinaColors.pink,
    path: '/subscriptions',
    group: AppMenuGroup.money,
    synonyms: ['tagihan', 'subscription', 'bayar rutin', 'bill', 'cicilan'],
  ),
  AppMenuItem(
    label: 'Proyeksi',
    icon: Icons.insights_rounded,
    color: GhinaColors.blue,
    path: '/forecast',
    group: AppMenuGroup.money,
    synonyms: ['forecast', 'rencana', 'perkiraan', 'bulan depan'],
  ),
  AppMenuItem(
    label: 'Laporan',
    icon: Icons.bar_chart_rounded,
    color: GhinaColors.red,
    path: '/reports',
    group: AppMenuGroup.money,
    synonyms: ['report', 'rekap', 'bulanan', 'tahunan'],
  ),
  AppMenuItem(
    label: 'Analitik',
    icon: Icons.donut_large_rounded,
    color: GhinaColors.yellow,
    path: '/analytics',
    group: AppMenuGroup.money,
    synonyms: ['analisis', 'statistik', 'grafik', 'chart', 'analytics', 'tren'],
  ),
  AppMenuItem(
    label: 'Investasi',
    icon: Icons.trending_up_rounded,
    color: GhinaColors.purple,
    path: '/investments',
    group: AppMenuGroup.money,
    synonyms: [
      'saham',
      'reksa dana',
      'reksadana',
      'kripto',
      'crypto',
      'emas',
      'obligasi',
      'portofolio',
      'invest',
    ],
  ),
  AppMenuItem(
    label: 'Kategori',
    icon: Icons.category_rounded,
    color: GhinaColors.purple,
    path: '/categories',
    group: AppMenuGroup.money,
    synonyms: ['category', 'jenis'],
  ),
  // ---- HIDUP
  AppMenuItem(
    label: 'Sholat',
    icon: Icons.mosque_rounded,
    color: GhinaColors.lime,
    path: '/prayers',
    group: AppMenuGroup.life,
    synonyms: ['salat', 'shalat', 'solat', 'doa', 'ibadah', 'prayer', 'masjid'],
  ),
  AppMenuItem(
    label: 'Kebiasaan',
    icon: Icons.self_improvement_rounded,
    color: GhinaColors.green,
    path: '/habits',
    group: AppMenuGroup.life,
    longPressPath: '/habits/new',
    synonyms: ['habit', 'rutinitas', 'berhenti', 'pengen', 'streak'],
  ),
  AppMenuItem(
    label: 'Kesehatan',
    icon: Icons.monitor_heart_rounded,
    color: GhinaColors.red,
    path: '/health',
    group: AppMenuGroup.life,
    synonyms: ['health', 'berat', 'tensi', 'tekanan darah', 'timbangan'],
  ),
  AppMenuItem(
    label: 'Makanan',
    icon: Icons.restaurant_rounded,
    color: GhinaColors.yellow,
    path: '/food',
    group: AppMenuGroup.life,
    synonyms: ['food', 'makan', 'kalori', 'diet', 'catatan makan'],
  ),
  // ---- PRODUKTIF
  AppMenuItem(
    label: 'Tugas',
    icon: Icons.checklist_rounded,
    color: GhinaColors.blue,
    path: '/tasks',
    group: AppMenuGroup.productive,
    isTab: true,
    synonyms: ['task', 'todo', 'to-do', 'kerjaan', 'pekerjaan', 'pengingat'],
  ),
  AppMenuItem(
    label: 'Catatan',
    icon: Icons.sticky_note_2_rounded,
    color: GhinaColors.orange,
    path: '/notes',
    group: AppMenuGroup.productive,
    longPressPath: '/notes/new',
    synonyms: ['note', 'notes', 'memo', 'ide', 'rekaman', 'suara'],
  ),
  AppMenuItem(
    label: 'Konten',
    icon: Icons.campaign_rounded,
    color: GhinaColors.purple,
    path: '/content',
    group: AppMenuGroup.productive,
    synonyms: ['content', 'sosmed', 'instagram', 'tiktok', 'posting', 'post'],
  ),
  // ---- LAINNYA
  AppMenuItem(
    label: 'Belajar',
    icon: Icons.school_rounded,
    color: GhinaColors.purple,
    path: '/learn',
    group: AppMenuGroup.other,
    synonyms: ['learn', 'pelajaran', 'kuis', 'lesson', 'edukasi'],
  ),
  AppMenuItem(
    label: 'Pencapaian',
    icon: Icons.emoji_events_rounded,
    color: GhinaColors.yellow,
    path: '/achievements',
    group: AppMenuGroup.other,
    synonyms: ['achievement', 'lencana', 'badge', 'trofi', 'xp', 'level'],
  ),
  AppMenuItem(
    label: 'Log Notifikasi',
    icon: Icons.notifications_active_rounded,
    color: GhinaColors.orange,
    path: '/notification-log',
    group: AppMenuGroup.other,
    androidOnly: true,
    synonyms: [
      'notifikasi',
      'notif',
      'notification',
      'otomatis',
      'auto',
      'rule',
      'aturan',
      'mutasi',
      'mbanking',
      'e-wallet',
    ],
  ),
  AppMenuItem(
    label: 'Sinkronisasi',
    icon: Icons.sync_rounded,
    color: GhinaColors.blue,
    path: '/sync',
    group: AppMenuGroup.other,
    synonyms: ['sync', 'sinkron', 'offline', 'cadangan', 'backup'],
  ),
  AppMenuItem(
    label: 'Pengaturan',
    icon: Icons.settings_rounded,
    color: GhinaColors.gray,
    path: '/settings',
    group: AppMenuGroup.other,
    synonyms: [
      'settings',
      'setting',
      'akun',
      'mata uang',
      'privasi',
      'kunci',
      'notifikasi',
      'keluar',
      'logout',
    ],
  ),
];

/// [kAppMenu] without the items this platform can't show ([AppMenuItem.androidOnly]).
List<AppMenuItem> get visibleAppMenu => [
  for (final i in kAppMenu)
    if (!i.androidOnly || defaultTargetPlatform == TargetPlatform.android) i,
];

/// The menu item with [path] (throws for unknown paths — a programming error).
AppMenuItem appMenuItem(String path) => kAppMenu.firstWhere(
  (i) => i.path == path,
  orElse: () => throw ArgumentError.value(path, 'path', 'not in kAppMenu'),
);

String _norm(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Items matching [query] by label, group name or a synonym, ignoring case
/// and punctuation. Words are matched by prefix ("lapor" → Laporan, "sa" →
/// saldo/saham/salat); when nothing matches, any substring counts. An empty
/// query returns every item. [items] defaults to [visibleAppMenu].
List<AppMenuItem> filterAppMenu(String query, [List<AppMenuItem>? only]) {
  final items = only ?? visibleAppMenu;
  final q = _norm(query);
  if (q.isEmpty) return items;
  List<AppMenuItem> where(bool Function(String) hit) => [
    for (final i in items)
      if (hit(i.label) || hit(i.group.label) || i.synonyms.any(hit)) i,
  ];
  bool prefix(String s) {
    final n = _norm(s);
    return n.startsWith(q) || n.contains(' $q');
  }

  final byPrefix = where(prefix);
  return byPrefix.isNotEmpty ? byPrefix : where((s) => _norm(s).contains(q));
}

/// Whether [item] is the screen at [location] (or one of its sub-pages).
bool isAppMenuItemActive(AppMenuItem item, String location) =>
    location == item.path || location.startsWith('${item.path}/');
