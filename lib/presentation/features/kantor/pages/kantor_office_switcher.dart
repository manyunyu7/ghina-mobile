import 'package:flutter/material.dart';
import '../session/kantor_feed.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../di/kantor_providers.dart';
import '../../../design_system/design_system.dart';
import '../agents/kantor_office_bar.dart';
import '../kantor_data.dart';
import '../roles/kantor_role.dart' show kantorErrorText;
import '../roles/kantor_ui.dart' show kantorToast;
import '../widgets/kantor_wide.dart';

/// "Pindah kantor" sheet: jump to another office, keeping the active tab.
/// With [onOffice], picking an office calls it instead of navigating (the
/// left pane of a wide session page only swaps its list).
Future<void> showKantorOfficeSwitcher(
  BuildContext context, {
  required String currentId,
  required String tab,
  void Function(String id)? onOffice,
}) {
  // The sheet navigates with the page's context; capture the router now.
  final router = GoRouter.of(context);
  return showChunkyBottomSheet<void>(
    context,
    title: 'Pindah kantor',
    builder: (sheet) => _SwitcherBody(
      currentId: currentId,
      onPick: (id) {
        Navigator.pop(sheet);
        if (id != null && onOffice != null) return onOffice(id);
        router.go(
          id == null
              ? '/kantor'
              : '/kantor/o/${Uri.encodeComponent(id)}?tab=$tab',
        );
      },
      onComplex: () {
        ProviderScope.containerOf(
          sheet,
        ).read(kantorSkipResumeProvider.notifier).set(true);
      },
    ),
  );
}

/// Warna tetap per kantor (dari namanya), sama di sheet dan bilah bawah.
ChunkySwatch kantorOfficeSwatch(String name) =>
    _palette[name.codeUnits.fold<int>(0, (a, c) => a + c) % _palette.length];

const _palette = [
  GhinaColors.blue,
  GhinaColors.green,
  GhinaColors.orange,
  GhinaColors.purple,
  GhinaColors.red,
  GhinaColors.yellow,
];

/// Tinggi minimum baris kantor yang padat di sheet "Pindah kantor".
const kKantorSwitcherRowHeight = 48.0;

class _SwitcherBody extends ConsumerStatefulWidget {
  const _SwitcherBody({
    required this.currentId,
    required this.onPick,
    required this.onComplex,
  });

  final String currentId;
  final void Function(String? id) onPick;
  final VoidCallback onComplex;

  @override
  ConsumerState<_SwitcherBody> createState() => _SwitcherBodyState();
}

class _SwitcherBodyState extends ConsumerState<_SwitcherBody> {
  String _query = '';
  bool _prefetched = false;

  /// Status favorit optimistis (id kantor -> fav) selama server belum
  /// mengirim nilai barunya. Dibuang begitu data server sudah sama.
  final _favOverride = <String, bool>{};

  /// Kantor yang permintaan favoritnya masih berjalan (cegah ketuk ganda).
  final _favBusy = <String>{};

  /// Favourites and offices with live agents are loaded as soon as the picker
  /// shows them, so the pick itself has nothing left to wait for.
  void _prefetch(List<Map<String, dynamic>> offices) {
    if (_prefetched || offices.isEmpty) return;
    _prefetched = true;
    final ids = [
      for (final o in offices)
        if (o['fav'] == true) '${o['id']}',
      for (final o in offices)
        if (o['fav'] != true && _live(o).isNotEmpty) '${o['id']}',
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) kantorPrefetchFeeds(ref, ids);
    });
  }

  bool _isFav(Map<String, dynamic> o) =>
      _favOverride['${o['id']}'] ?? o['fav'] == true;

  /// Favorit/unfavorit langsung dari sheet: bintang berubah seketika, lalu
  /// POST ke server dan muat ulang state (bilah bawah ikut berubah). Gagal:
  /// bintang dikembalikan dan muncul toast.
  Future<void> _toggleFav(Map<String, dynamic> o) async {
    final id = '${o['id']}';
    if (!_favBusy.add(id)) return;
    final next = !_isFav(o);
    setState(() => _favOverride[id] = next);
    try {
      final api = ref.read(kantorApiProvider);
      if (api == null) {
        throw const KantorException(
          KantorFailure.unauthorized,
          'Token Kantor belum diisi.',
        );
      }
      await api.post('/api/offices/${Uri.encodeComponent(id)}/fav', {
        'fav': next,
      });
      if (mounted) ref.invalidate(kantorStateProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() => _favOverride.remove(id));
      kantorToast(
        context,
        '${next ? 'Gagal memfavoritkan' : 'Gagal menghapus favorit'} '
        '${o['name']}: ${kantorErrorText(e)}',
        bad: true,
      );
    } finally {
      _favBusy.remove(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final async = ref.watch(kantorStateProvider);
    final offices = (async.value?['offices'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    _prefetch(offices);
    // nilai optimistis yang sudah sama dengan server tidak diperlukan lagi
    // (permintaan yang masih berjalan dibiarkan)
    _favOverride.removeWhere(
      (id, fav) =>
          !_favBusy.contains(id) &&
          offices.any((o) => '${o['id']}' == id && (o['fav'] == true) == fav),
    );
    final q = _query.trim().toLowerCase();
    bool match(Map<String, dynamic> o) =>
        q.isEmpty || '${o['name']}'.toLowerCase().contains(q);
    // Favorit di atas, lalu yang sedang ada agen (terbanyak dulu), lalu sisanya.
    final favs = offices.where((o) => _isFav(o) && match(o)).toList();
    final active =
        offices
            .where((o) => !_isFav(o) && _live(o).isNotEmpty && match(o))
            .toList()
          ..sort((a, b) => _live(b).length - _live(a).length);
    final rest = offices
        .where((o) => !_isFav(o) && _live(o).isEmpty && match(o))
        .toList();

    Widget row(Map<String, dynamic> o) {
      final id = '${o['id']}';
      return _OfficeRow(
        key: ValueKey('office-row-$id'),
        office: o,
        fav: _isFav(o),
        current: id == widget.currentId,
        onTap: () => widget.onPick(id),
        onFav: () => _toggleFav(o),
      );
    }

    // The sheet itself scrolls (ChunkyBottomSheet) and would give this list
    // unbounded height: then the list takes the drags but never moves. Bound
    // it so the list scrolls to its last office. The search sits below the
    // list, near the thumb (the sheet lifts it above the keyboard).
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.72,
      ),
      // skala teks sistem dibatasi supaya baris padat tidak meluap
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: LayoutBuilder(
          builder: (context, box) {
            // Layar lebar (sheet ±600dp): baris disusun 2 kolom supaya tidak
            // melebar penuh; layar sempit tetap 1 kolom.
            final cols = kantorIsWide(context)
                ? kantorGridColumns(box.maxWidth, minTile: 260, max: 2)
                : 1;
            List<Widget> grid(List<Map<String, dynamic>> list) => [
              for (var i = 0; i < list.length; i += cols)
                if (cols == 1)
                  row(list[i])
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var j = 0; j < cols; j++) ...[
                        if (j > 0) const SizedBox(width: GhinaSpace.sm),
                        Expanded(
                          child: i + j < list.length
                              ? row(list[i + j])
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
            ];
            final grouped = favs.isNotEmpty || active.isNotEmpty;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flexible(
                  child: ListView(
                    key: const ValueKey('office-switcher-list'),
                    shrinkWrap: true,
                    children: [
                      if (q.isEmpty)
                        _CompactRow(
                          key: const ValueKey('office-row-_kompleks'),
                          icon: Icons.apartment_rounded,
                          iconColor: g.textSecondary,
                          title: 'Kompleks (semua kantor)',
                          current: widget.currentId == '_kompleks',
                          onTap: () {
                            widget.onComplex();
                            widget.onPick(null);
                          },
                        ),
                      if (async.hasError && offices.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(GhinaSpace.md),
                          child: Text(
                            'Daftar kantor gagal dimuat.',
                            style: GhinaType.caption.copyWith(
                              color: g.textMuted,
                            ),
                          ),
                        ),
                      if (favs.isNotEmpty) ...[
                        const _SectionLabel('Favorit'),
                        ...grid(favs),
                      ],
                      if (active.isNotEmpty) ...[
                        const _SectionLabel('Sedang aktif'),
                        ...grid(active),
                      ],
                      if (rest.isNotEmpty) ...[
                        _SectionLabel(grouped ? 'Lainnya' : 'Semua kantor'),
                        ...grid(rest),
                      ] else if (!grouped)
                        const EmptyState(
                          title: 'Tidak ada kantor',
                          compact: true,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: GhinaSpace.sm),
                ChunkyTextField(
                  hint: 'Cari kantor…',
                  prefixIcon: Icons.search_rounded,
                  onChanged: (v) => setState(() => _query = v),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

List<Map<String, dynamic>> _live(Map<String, dynamic> o) =>
    (o['sessions'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((s) => s['status'] != 'ended')
        .toList();

/// Judul bagian yang kecil (bukan SectionHeader besar) supaya daftar padat.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      GhinaSpace.xs,
      GhinaSpace.md,
      GhinaSpace.xs,
      GhinaSpace.xs,
    ),
    child: Text(
      title,
      style: GhinaType.caption.w(800).copyWith(color: context.ghina.textMuted),
    ),
  );
}

/// Baris kantor padat (±48dp): ikon kecil, nama satu baris + status singkat,
/// badge pil seperti bilah bawah, centang kantor aktif, dan bintang favorit.
/// Tahan lama baris = favorit/unfavorit juga.
class _OfficeRow extends StatelessWidget {
  const _OfficeRow({
    super.key,
    required this.office,
    required this.fav,
    required this.current,
    required this.onTap,
    required this.onFav,
  });

  final Map<String, dynamic> office;
  final bool fav;
  final bool current;
  final VoidCallback onTap;
  final VoidCallback onFav;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final name = '${office['name']}';
    final sessions = _live(office);
    final working = sessions.where((s) => s['status'] == 'working').length;
    final style = '${office['style'] ?? ''}';
    final status = sessions.isEmpty
        ? 'sepi'
        : '${sessions.length} sesi · $working bekerja';
    return _CompactRow(
      icon: Icons.apartment_rounded,
      iconColor: kantorOfficeSwatch(name).base,
      title: name,
      subtitle: [status, if (style.isNotEmpty) style].join(' · '),
      current: current,
      onTap: onTap,
      onLongPress: onFav,
      trailing: [
        // Pil badge yang sama dengan bilah bawah (min 20dp, 11sp tebal):
        // merah = agen menunggu izin, biru = ada yang bekerja.
        if (KantorOfficeBadgeData.of(office) case final b?)
          KantorOfficeBadge(b),
      ],
      // bintang paling kanan, dekat jempol
      action: IconButton(
        key: ValueKey('office-fav-${office['id']}'),
        tooltip: fav ? 'Hapus dari favorit' : 'Jadikan favorit',
        onPressed: onFav,
        iconSize: 20,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        icon: Icon(
          fav ? Icons.star_rounded : Icons.star_border_rounded,
          color: fav ? GhinaColors.yellow.base : g.textMuted,
        ),
      ),
    );
  }
}

/// Kerangka baris padat yang dipakai baris kantor dan "Kompleks".
class _CompactRow extends StatelessWidget {
  const _CompactRow({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.current,
    required this.onTap,
    this.subtitle,
    this.onLongPress,
    this.trailing = const [],
    this.action,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final bool current;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final List<Widget> trailing;

  /// Tombol paling kanan (bintang favorit).
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final subtitle = this.subtitle;
    return Material(
      // kantor aktif disorot dengan latar warna aksen yang lembut
      color: current ? g.highlight.tint(g.brightness) : Colors.transparent,
      borderRadius: GhinaRadii.rMd,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: kKantorSwitcherRowHeight,
          ),
          child: Padding(
            padding: const EdgeInsets.only(left: GhinaSpace.sm),
            child: Row(
              children: [
                Icon(icon, size: 20, color: iconColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                          style: GhinaType.body
                              .w(800)
                              .copyWith(color: g.textPrimary, height: 1.25),
                        ),
                        if (subtitle != null && subtitle.isNotEmpty)
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                            style: GhinaType.caption.copyWith(
                              color: g.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                for (final w in trailing) ...[
                  const SizedBox(width: GhinaSpace.xs),
                  w,
                ],
                if (current) ...[
                  const SizedBox(width: GhinaSpace.xs),
                  Icon(
                    Icons.check_rounded,
                    key: const ValueKey('office-row-current'),
                    size: 20,
                    color: g.highlight.base,
                  ),
                ],
                if (action case final a?) ...[
                  const SizedBox(width: 2),
                  a,
                  const SizedBox(width: 2),
                ] else
                  // tanpa bintang (baris Kompleks): jarak kanan tetap
                  const SizedBox(width: GhinaSpace.md),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
