import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/design_system.dart';
import '../kantor_data.dart';
import '../pages/kantor_office_switcher.dart';
import '../session/kantor_feed.dart';

/// Tinggi bilah ganti kantor (tanpa inset bawah). Chip di dalamnya 44dp.
const kKantorOfficeBarHeight = 56.0;

/// Kantor untuk chip bilah bawah: favorit, lalu kantor lain yang sedang ada
/// agen aktif (terbanyak dulu). Kantor [currentId] selalu ikut (paling depan
/// bila bukan favorit/aktif) supaya kantor aktif selalu terlihat disorot.
List<Map<String, dynamic>> kantorBarOffices(
  List<Map<String, dynamic>> offices,
  String currentId,
) {
  int live(Map<String, dynamic> o) => (o['sessions'] as List? ?? const [])
      .where((s) => s is Map && s['status'] != 'ended')
      .length;
  final favs = [
    for (final o in offices)
      if (o['fav'] == true) o,
  ];
  final active = [
    for (final o in offices)
      if (o['fav'] != true && live(o) > 0) o,
  ]..sort((a, b) => live(b) - live(a));
  final picked = [...favs, ...active];
  if (!picked.any((o) => '${o['id']}' == currentId)) {
    final cur = offices.where((o) => '${o['id']}' == currentId);
    if (cur.isNotEmpty) picked.insert(0, cur.first);
  }
  return picked;
}

/// Bilah ganti kantor di bawah daftar agen, di jangkauan jempol: chip kantor
/// favorit dan yang sedang aktif (geser horizontal), kantor aktif disorot, dan
/// chip terakhir "Semua…" (tetap di kanan) membuka sheet "Pindah kantor".
///
/// Ketuk chip berperilaku sama dengan memilih di sheet: dengan [onOffice]
/// hanya memanggilnya (panel kiri halaman sesi), tanpa itu pindah ke halaman
/// kantor itu dengan tab [tab]. Feed kantor-kantor di chip dimuat lebih dulu
/// begitu bilah tampil, jadi ketukan langsung menampilkan agennya.
class KantorOfficeBar extends ConsumerStatefulWidget {
  const KantorOfficeBar({
    super.key,
    required this.currentId,
    this.tab = 'agen',
    this.onOffice,
  });

  final String currentId;
  final String tab;
  final void Function(String id)? onOffice;

  @override
  ConsumerState<KantorOfficeBar> createState() => _KantorOfficeBarState();
}

class _KantorOfficeBarState extends ConsumerState<KantorOfficeBar> {
  /// Kantor yang sudah di-prefetch, supaya tiap rebuild tidak mengulang.
  final _prefetched = <String>{};

  void _prefetch(List<String> ids) {
    final todo = [
      for (final id in ids)
        if (id != widget.currentId && !_prefetched.contains(id)) id,
    ];
    if (todo.isEmpty) return;
    _prefetched.addAll(todo);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) kantorPrefetchFeeds(ref, todo);
    });
  }

  void _pick(String id) {
    if (id == widget.currentId) return;
    final onOffice = widget.onOffice;
    if (onOffice != null) return onOffice(id);
    GoRouter.of(
      context,
    ).go('/kantor/o/${Uri.encodeComponent(id)}?tab=${widget.tab}');
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    // keyboard terbuka (cari agen, mengetik chat): beri ruang ke isi
    if (MediaQuery.viewInsetsOf(context).bottom > 0) {
      return const SizedBox.shrink();
    }
    final offices =
        (ref.watch(kantorStateProvider).value?['offices'] as List? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
    final chips = kantorBarOffices(offices, widget.currentId);
    _prefetch([for (final o in chips) '${o['id']}']);

    Widget chip(Widget child) => Padding(
      padding: const EdgeInsets.only(right: GhinaSpace.sm),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: child,
        ),
      ),
    );

    return Material(
      key: const ValueKey('kantor-office-bar'),
      color: g.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: g.border)),
        ),
        // inset bawah: gesture bar / tombol navigasi sistem
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: kKantorOfficeBarHeight,
            child: Row(
              children: [
                Expanded(
                  child: ListView(
                    key: const ValueKey('kantor-office-bar-list'),
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(left: GhinaSpace.md),
                    children: [
                      for (final o in chips)
                        chip(
                          ChunkyChip(
                            key: ValueKey('office-chip-${o['id']}'),
                            label: '${o['name'] ?? o['id']}',
                            icon: o['fav'] == true
                                ? Icons.star_rounded
                                : Icons.apartment_rounded,
                            color: kantorOfficeSwatch('${o['name']}'),
                            selected: '${o['id']}' == widget.currentId,
                            onTap: () => _pick('${o['id']}'),
                          ),
                        ),
                    ],
                  ),
                ),
                // chip terakhir, selalu terlihat (tidak ikut tergeser)
                Padding(
                  padding: const EdgeInsets.only(
                    left: GhinaSpace.xs,
                    right: GhinaSpace.md - GhinaSpace.sm,
                  ),
                  child: chip(
                    ChunkyChip(
                      key: const ValueKey('office-chip-all'),
                      label: 'Semua…',
                      icon: Icons.unfold_more_rounded,
                      selected: false,
                      onTap: () => showKantorOfficeSwitcher(
                        context,
                        currentId: widget.currentId,
                        tab: widget.tab,
                        onOffice: widget.onOffice,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
