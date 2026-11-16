import 'package:flutter/material.dart';
import '../session/kantor_feed.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/design_system.dart';
import '../kantor_data.dart';

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

const _palette = [
  GhinaColors.blue,
  GhinaColors.green,
  GhinaColors.orange,
  GhinaColors.purple,
  GhinaColors.red,
  GhinaColors.yellow,
];

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

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final async = ref.watch(kantorStateProvider);
    final offices = (async.value?['offices'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    _prefetch(offices);
    final q = _query.trim().toLowerCase();
    bool match(Map<String, dynamic> o) =>
        q.isEmpty || '${o['name']}'.toLowerCase().contains(q);
    final live = offices.where((o) => _live(o).isNotEmpty).toList();
    final favs = offices.where((o) => o['fav'] == true && match(o)).toList();
    final active = live.where((o) => o['fav'] != true && match(o)).toList()
      ..sort((a, b) => _live(b).length - _live(a).length);
    final rest = offices.where(match).toList();

    Widget row(Map<String, dynamic> o) => _OfficeRow(
      office: o,
      current: '${o['id']}' == widget.currentId,
      onTap: () => widget.onPick('${o['id']}'),
    );

    // The sheet itself scrolls (ChunkyBottomSheet) and would give this list
    // unbounded height: then the list takes the drags but never moves. Bound
    // it so the search stays on top and the list scrolls to its last office.
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.72,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ChunkyTextField(
            hint: 'Cari kantor…',
            prefixIcon: Icons.search_rounded,
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: GhinaSpace.sm),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                if (q.isEmpty)
                  ChunkyTile(
                    leading: const Icon(Icons.apartment_rounded),
                    title: 'Kompleks (semua kantor)',
                    trailing: widget.currentId == '_kompleks'
                        ? const Icon(Icons.check_rounded)
                        : null,
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
                      style: GhinaType.caption.copyWith(color: g.textMuted),
                    ),
                  ),
                if (favs.isNotEmpty) ...[
                  const SectionHeader(title: 'Favorit'),
                  for (final o in favs) row(o),
                ],
                if (active.isNotEmpty) ...[
                  const SectionHeader(title: 'Sedang aktif'),
                  for (final o in active) row(o),
                ],
                const SectionHeader(title: 'Semua kantor'),
                if (rest.isEmpty)
                  const EmptyState(title: 'Tidak ada kantor', compact: true)
                else
                  for (final o in rest) row(o),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

List<Map<String, dynamic>> _live(Map<String, dynamic> o) =>
    (o['sessions'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((s) => s['status'] != 'ended')
        .toList();

class _OfficeRow extends StatelessWidget {
  const _OfficeRow({
    required this.office,
    required this.current,
    required this.onTap,
  });

  final Map<String, dynamic> office;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = '${office['name']}';
    final sessions = _live(office);
    final working = sessions.where((s) => s['status'] == 'working').length;
    final waiting = sessions.where((s) => s['waiting'] != null).length;
    final color =
        _palette[name.codeUnits.fold<int>(0, (a, c) => a + c) %
            _palette.length];
    final style = '${office['style'] ?? ''}';
    final status = sessions.isEmpty
        ? 'sepi'
        : '${sessions.length} sesi · $working bekerja';
    return ChunkyTile(
      leading: Icon(Icons.apartment_rounded, color: color.base),
      title: name,
      subtitle: [if (style.isNotEmpty) style, status].join(' · '),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (waiting > 0)
            Badge(label: Text('$waiting'), child: const SizedBox(width: 20)),
          if (current) const Icon(Icons.check_rounded),
        ],
      ),
      onTap: onTap,
    );
  }
}
