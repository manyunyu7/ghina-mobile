import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/design_system.dart';
import '../kantor_data.dart';
import '../pages/kantor_office_switcher.dart';
import '../session/kantor_feed.dart';

/// Tinggi bilah ganti kantor (tanpa inset bawah). Chip di dalamnya min 44dp,
/// badge di chip min 20dp (sebaris dengan nama, tidak di sudut).
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
      child: Center(child: child),
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
          // tinggi bilah tetap: skala teks sistem dibatasi supaya chip dan
          // badge tidak meluap/terpotong
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.2,
            child: SizedBox(
              height: kKantorOfficeBarHeight,
              child: LayoutBuilder(
                builder: (context, box) {
                  // panel sempit (panel kiri dua-panel ±330dp): "Semua…"
                  // cukup ikon supaya chip kantor dapat ruang lebih
                  final narrow = box.maxWidth < 360;
                  // lebar maksimum chip: nama dielipsis di dalamnya, badge
                  // selalu utuh di kanan
                  final maxChip = (box.maxWidth * 0.6).clamp(140.0, 240.0);
                  return Row(
                    children: [
                      Expanded(
                        child: ListView(
                          key: const ValueKey('kantor-office-bar-list'),
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.only(left: GhinaSpace.md),
                          children: [
                            for (final o in chips)
                              chip(
                                KantorOfficeChip(
                                  key: ValueKey('office-chip-${o['id']}'),
                                  label: '${o['name'] ?? o['id']}',
                                  icon: o['fav'] == true
                                      ? Icons.star_rounded
                                      : Icons.apartment_rounded,
                                  color: kantorOfficeSwatch('${o['name']}'),
                                  selected: '${o['id']}' == widget.currentId,
                                  badge: KantorOfficeBadgeData.of(o),
                                  maxWidth: maxChip,
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
                          KantorOfficeChip(
                            key: const ValueKey('office-chip-all'),
                            label: 'Semua…',
                            icon: Icons.unfold_more_rounded,
                            selected: false,
                            iconOnly: narrow,
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
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Isi badge chip kantor: jumlah dan nada warnanya.
@immutable
class KantorOfficeBadgeData {
  const KantorOfficeBadgeData(this.count, this.tone);

  final int count;
  final KantorBadgeTone tone;

  /// Badge untuk [office]: agen yang menunggu izin (perlu tindakan, merah)
  /// didahulukan; selain itu jumlah agen hidup (biru/aksen bila ada yang
  /// bekerja, netral bila semua idle). Null bila kantor sepi.
  static KantorOfficeBadgeData? of(Map<String, dynamic> office) {
    final live = [
      for (final s in (office['sessions'] as List? ?? const []))
        if (s is Map && s['status'] != 'ended') s,
    ];
    if (live.isEmpty) return null;
    final waiting = live.where((s) => s['waiting'] != null).length;
    if (waiting > 0) {
      return KantorOfficeBadgeData(waiting, KantorBadgeTone.action);
    }
    final working = live.any((s) => s['status'] == 'working');
    return KantorOfficeBadgeData(
      live.length,
      working ? KantorBadgeTone.active : KantorBadgeTone.quiet,
    );
  }

  /// Teks badge: angka besar disingkat jadi "99+".
  String get text => count > 99 ? '99+' : '$count';

  /// Label pembaca layar.
  String get semantic => switch (tone) {
    KantorBadgeTone.action => '$count perlu tindakan',
    KantorBadgeTone.active => '$count agen, ada yang bekerja',
    KantorBadgeTone.quiet => '$count agen idle',
  };
}

enum KantorBadgeTone { action, active, quiet }

/// Chip kantor di bilah bawah: ikon, nama (elipsis bila panjang) dan badge
/// sebaris di kanan. Badge bagian dari baris (bukan tumpukan di sudut), jadi
/// tidak pernah terpotong tinggi bilah ataupun clip; yang mengalah hanya nama.
class KantorOfficeChip extends StatelessWidget {
  const KantorOfficeChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.color,
    this.badge,
    this.maxWidth = 240,
    this.iconOnly = false,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  /// Null = `context.ghina.highlight`.
  final ChunkySwatch? color;
  final KantorOfficeBadgeData? badge;

  /// Lebar maksimum chip; nama dielipsis supaya badge tetap utuh.
  final double maxWidth;

  /// Hanya ikon (label tetap jadi label semantik), untuk panel sempit.
  final bool iconOnly;

  /// Tinggi minimum chip (target sentuh).
  static const minHeight = 44.0;

  /// Tinggi minimum badge.
  static const badgeMinSize = 20.0;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final b = g.brightness;
    final color = this.color ?? g.highlight;
    final fg = selected ? color.base : g.textSecondary;
    final badge = this.badge;
    final semantic = [label, if (badge != null) badge.semantic].join(', ');
    return AnimatedScale(
      scale: selected ? 1.0 : 0.98,
      duration: GhinaMotion.fast,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: minHeight,
          minWidth: minHeight,
          maxWidth: iconOnly ? double.infinity : maxWidth,
        ),
        child: ChunkySurface(
          color: selected ? color.tint(b) : g.surface,
          edgeColor: selected ? color.tintBorder(b) : g.borderEdge,
          // kantor aktif: garis tepi warna penuh supaya jelas terlihat
          borderColor: selected ? color.base : g.border,
          depth: GhinaDepth.sm,
          borderRadius: GhinaRadii.rMd,
          padding: EdgeInsets.symmetric(
            horizontal: iconOnly ? 10 : 12,
            vertical: 8,
          ),
          onTap: onTap,
          semanticLabel: semantic,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) Icon(icon, size: 18, color: fg),
              if (!iconOnly) ...[
                if (icon != null) const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: GhinaType.body.w(800).copyWith(color: fg),
                  ),
                ),
              ],
              if (badge != null) ...[
                const SizedBox(width: 8),
                KantorOfficeBadge(badge),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Pil badge: min 20×20dp, angka 11sp tebal, warna dari colorScheme.
class KantorOfficeBadge extends StatelessWidget {
  const KantorOfficeBadge(this.data, {super.key});

  final KantorOfficeBadgeData data;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (bg, fg) = switch (data.tone) {
      KantorBadgeTone.action => (cs.error, cs.onError),
      KantorBadgeTone.active => (cs.primary, cs.onPrimary),
      KantorBadgeTone.quiet => (cs.surfaceContainerHighest, cs.onSurface),
    };
    return ExcludeSemantics(
      child: Container(
        key: const ValueKey('office-chip-badge'),
        constraints: const BoxConstraints(
          minWidth: KantorOfficeChip.badgeMinSize,
          minHeight: KantorOfficeChip.badgeMinSize,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(KantorOfficeChip.badgeMinSize),
        ),
        child: Text(
          data.text,
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            height: 1.0,
            color: fg,
          ),
        ),
      ),
    );
  }
}
